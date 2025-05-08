#!/usr/bin/env bash
set -euo pipefail
export AWS_PAGER=""

# ------------------------------------------------------------------------------
# VARIABLES DE ENTORNO IN-LINE
# ------------------------------------------------------------------------------
set -a
AWS_ACCOUNT_ID=774305595347
AWS_REGION=us-east-1

REPO_NAME=blacklist-api
REPO_OWNER=japago25andes
BRANCH=main

CLUSTER_NAME=blacklist-api-cluster
SERVICE_NAME=blacklist-api-service-fargate
TASK_FAMILY=blacklist-task-definition

DB_INSTANCE_ID=blacklist-db
DB_USERNAME=blacklist_user
DB_PASSWORD=blacklist_password
DB_NAME=blacklist_db

VPC_ID=vpc-0ea87756eab16d187
LOG_GROUP=blacklist-api-logs

AUTH_TOKEN=mi_token_super_secreto

ALB_NAME=blacklist-alb
TG_BLUE_NAME=blacklist-tg-blue
TG_GREEN_NAME=blacklist-tg-green

CD_APP_NAME=blacklist-api-cd-app
CD_DG_NAME=blacklist-api-cd-dg

S3_BUCKET=blacklist-pipeline-artifacts-${AWS_ACCOUNT_ID}
WEBHOOK_NAME=blacklist-webhook
GITHUB_PAT=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
GITHUB_WEBHOOK_SECRET=9f2d3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f

AWS_COMMON="--region ${AWS_REGION}"

# ------------------------------------------------------------------------------
# A. FUNCIONES AUXILIARES
# ------------------------------------------------------------------------------
ensure_sg() {
  local name=$1 desc=$2
  local sg
  sg=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$name" Name=vpc-id,Values="$VPC_ID" \
    ${AWS_COMMON} \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
  if [[ -n "$sg" && "$sg" != "None" ]]; then
    echo "$sg"
  else
    aws ec2 create-security-group \
      --group-name "$name" \
      --description "$desc" \
      --vpc-id "$VPC_ID" \
      ${AWS_COMMON} \
      --query GroupId --output text
  fi
}

authorize_ingress() {
  local sg=$1 proto=$2 port=$3 cidr=$4 src=$5
  aws ec2 authorize-security-group-ingress \
    --group-id $sg --protocol $proto --port $port \
    ${cidr:+--cidr $cidr} \
    ${src:+--source-group $src} \
    ${AWS_COMMON} 2>/dev/null || true
}

ensure_tg() {
  local name=$1
  aws elbv2 describe-target-groups --names "$name" ${AWS_COMMON} \
    --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || \
  aws elbv2 create-target-group \
    --name "$name" \
    --protocol HTTP --port 5000 --vpc-id "$VPC_ID" \
    --health-check-protocol HTTP --health-check-path /health \
    --health-check-interval-seconds 30 --healthy-threshold-count 3 --unhealthy-threshold-count 5 \
    --target-type ip \
    ${AWS_COMMON} \
    --query "TargetGroups[0].TargetGroupArn" --output text
}

ensure_cluster() {
  local name=$1
  # Intentamos describir el cluster
  local status
  status=$(aws ecs describe-clusters \
    --clusters "$name" \
    ${AWS_COMMON} \
    --query "clusters[0].status" \
    --output text 2>/dev/null || echo "NOTFOUND")

  if [[ "$status" == "ACTIVE" ]]; then
    # Ya existe y está activo
    echo "$name"
  elif [[ "$status" == "INACTIVE" ]]; then
    echo "⚠️ Cluster '$name' está INACTIVE, borrando y recreando..."
    aws ecs delete-cluster --cluster "$name" ${AWS_COMMON}
    aws ecs create-cluster --cluster-name "$name" ${AWS_COMMON} \
      --query "cluster.clusterName" --output text
  else
    # No existe
    echo "➕ Creando cluster '$name'..."
    aws ecs create-cluster --cluster-name "$name" ${AWS_COMMON} \
      --query "cluster.clusterName" --output text
  fi
}


ensure_ecr_repo() {
  local repo_name="$REPO_NAME"
  # Comprueba si el repositorio ya existe
  if aws ecr describe-repositories \
       --repository-names "$repo_name" \
       ${AWS_COMMON} \
       >/dev/null 2>&1; then
    echo "✅ ECR repository '$repo_name' already exists."
  else
    echo "🚀 Creating ECR repository '$repo_name'..."
    aws ecr create-repository \
      --repository-name "$repo_name" \
      ${AWS_COMMON} \
      --query "repository.repositoryName" \
      --output text \
    && echo "✅ Repository '$repo_name' created."
    echo "🐳 Building image…"
    docker build -t $REPO_NAME:latest .
    aws ecr get-login-password ${AWS_COMMON} | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.${AWS_REGION}.amazonaws.com
    echo "🔄 Pushing image…"
    docker tag $REPO_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_NAME:latest
    docker push $AWS_ACCOUNT_ID.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_NAME:latest
  fi
}
ensure_log_group() {
  local lg=$1
  if aws logs describe-log-groups \
       --log-group-name-prefix "$lg" \
       ${AWS_COMMON} \
       --query "logGroups[?logGroupName=='$lg']" \
       --output text | grep -q "^$lg$"; then
    echo "$lg"
  else
    aws logs create-log-group \
      --log-group-name "$lg" \
      ${AWS_COMMON}
    echo "$lg"
  fi
}

ensure_service_action() {
  local cluster=$1 service=$2
  aws ecs describe-services --cluster "$cluster" --services "$service" ${AWS_COMMON} \
    --query "services[0].status" --output text 2>/dev/null | grep -qE 'ACTIVE|DRAINING' && echo "exists" || echo "create"
}

# ------------------------------------------------------------------------------
# 1. SUBNETS
# ------------------------------------------------------------------------------
echo "🔍 Obteniendo subnets…"
SUBNETS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="${VPC_ID}" \
  ${AWS_COMMON} \
  --query "Subnets[].SubnetId" --output text)
read -r -a SUBNET_ARRAY <<<"$SUBNETS"

# ------------------------------------------------------------------------------
# 2. SECURITY GROUPS
# ------------------------------------------------------------------------------
echo "🛡️  Asegurando Security Groups…"
SG_RDS=$(ensure_sg "postgres-bs-sg" "RDS Postgres Free Tier")
SG_ALB=$(ensure_sg "alb-bs-sg"      "ALB for blacklist-api")
SG_TASK=$(ensure_sg "task-bs-sg"    "Fargate SG for blacklist-api")

# Solo permitir RDS desde el SG de la tarea
authorize_ingress "$SG_RDS" tcp 5432 "" "$SG_TASK"
authorize_ingress "$SG_ALB" tcp 80 0.0.0.0/0 ""
authorize_ingress "$SG_TASK" tcp 5000 "" "$SG_ALB"

echo "  → RDS SG:  $SG_RDS"
echo "  → ALB SG:  $SG_ALB"
echo "  → TASK SG: $SG_TASK"

# ------------------------------------------------------------------------------
# 3. RDS POSTGRES
# ------------------------------------------------------------------------------
echo "🗄️  Asegurando instancia RDS…"
if ! aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" ${AWS_COMMON} >/dev/null 2>&1; then
  aws rds create-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --db-instance-class db.t3.micro \
    --engine postgres --engine-version 15 \
    --allocated-storage 20 \
    --master-username "$DB_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --vpc-security-group-ids "$SG_RDS" \
    --no-multi-az --storage-type gp2 --backup-retention-period 0 \
    ${AWS_COMMON}
  aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID" ${AWS_COMMON}
fi

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" ${AWS_COMMON} \
  --query "DBInstances[0].Endpoint.Address" --output text)
echo "  → RDS endpoint: $DB_ENDPOINT"

# ------------------------------------------------------------------------------
# 4. ECS CLUSTER
# ------------------------------------------------------------------------------
echo "🚧 Asegurando ECS Cluster…"
CLUSTER_NAME=$(ensure_cluster "$CLUSTER_NAME")
echo "  → ECS Cluster: $CLUSTER_NAME"

# ------------------------------------------------------------------------------
# 5. ECR REPO + BUILD & PUSH
# ------------------------------------------------------------------------------
echo "🐋 Asegurando ECR repo…"
ensure_ecr_repo


# ------------------------------------------------------------------------------
# 6. LOG GROUP
# ------------------------------------------------------------------------------
echo "📑 Asegurando Log Group…"
LOG_GROUP=$(ensure_log_group "$LOG_GROUP")
echo "  → LogGroup: $LOG_GROUP"

# ------------------------------------------------------------------------------
# 7. ALB & TARGET GROUPS
# ------------------------------------------------------------------------------
echo "🌐 Asegurando Load Balancer…"
TG_BLUE_ARN=$(ensure_tg "$TG_BLUE_NAME")
TG_GREEN_ARN=$(ensure_tg "$TG_GREEN_NAME")

ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" ${AWS_COMMON} \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || \
  aws elbv2 create-load-balancer \
    --name "$ALB_NAME" \
    --subnets ${SUBNET_ARRAY[@]} \
    --security-groups "$SG_ALB" \
    --scheme internet-facing \
    --type application \
    ${AWS_COMMON} \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)

# Listener azul (puerto 80)
if aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" ${AWS_COMMON} \
     --query "Listeners[?Port==\`80\`]" --output text | grep -q .; then
  LISTENER_ARN=$(aws elbv2 modify-listener \
    --listener-arn $(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" ${AWS_COMMON} \
      --query "Listeners[?Port==\`80\`].ListenerArn" --output text) \
    --default-actions Type=forward,TargetGroupArn="$TG_BLUE_ARN" \
    ${AWS_COMMON} --query "Listeners[0].ListenerArn" --output text)
else
  LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_BLUE_ARN" \
    ${AWS_COMMON} --query "Listeners[0].ListenerArn" --output text)
fi

# Listener verde de prueba (puerto 8080)
if aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" ${AWS_COMMON} \
     --query "Listeners[?Port==\`8080\`]" --output text | grep -q .; then
  TEST_LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
    ${AWS_COMMON} --query "Listeners[?Port==\`8080\`].ListenerArn" --output text)
else
  TEST_LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 8080 \
    --default-actions Type=forward,TargetGroupArn="$TG_GREEN_ARN" \
    ${AWS_COMMON} --query "Listeners[0].ListenerArn" --output text)
fi

echo "  → ALB ARN:        $ALB_ARN"
echo "  → Blue TG ARN:    $TG_BLUE_ARN"
echo "  → Green TG ARN:   $TG_GREEN_ARN"
echo "  → Listener 80:    $LISTENER_ARN"
echo "  → Listener 8080:  $TEST_LISTENER_ARN"

# ------------------------------------------------------------------------------
# 8. ECS TASK DEFINITION
# ------------------------------------------------------------------------------
# Generar JSON a partir de plantilla
envsubst < infra/task-definition.json.tpl > infra/task-definition.json

EXISTING_TASK_DEF_ARN=$(aws ecs list-task-definitions \
  --family-prefix "$TASK_FAMILY" \
  --status ACTIVE \
  --max-items 1 \
  --query 'taskDefinitionArns[0]' \
  --output text ${AWS_COMMON})

if [[ "$EXISTING_TASK_DEF_ARN" == "None" ]]; then
  echo "➕ No existen Task Definitions para '$TASK_FAMILY'. Registrando la primera..."
  NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://infra/task-definition.json \
    ${AWS_COMMON} \
    --query "taskDefinition.taskDefinitionArn" \
    --output text)
  echo "→ Nueva TaskDef ARN: $NEW_TASK_DEF_ARN"
else
  echo "✅ Ya existe al menos una Task Definition: $EXISTING_TASK_DEF_ARN"
  NEW_TASK_DEF_ARN=$EXISTING_TASK_DEF_ARN
fi

# ------------------------------------------------------------------------------
# 9. ECS SERVICE
# ------------------------------------------------------------------------------
echo "🔄 Asegurando ECS Service…"

ACTION=$(ensure_service_action "$CLUSTER_NAME" "$SERVICE_NAME")
if [[ "$ACTION" == "create" ]]; then
  SUBNET_CSV=$(IFS=,; echo "${SUBNET_ARRAY[*]}")
  aws ecs create-service \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --task-definition "$NEW_TASK_DEF_ARN" \
    --desired-count 1 \
    --launch-type FARGATE \
    --deployment-controller type=CODE_DEPLOY \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_CSV}],securityGroups=[${SG_TASK}],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_BLUE_ARN,containerName=blacklist-api,containerPort=5000" \
    ${AWS_COMMON}
  echo "  → ECS Service creado: $SERVICE_NAME"
fi

# ------------------------------------------------------------------------------
# 10. CI/CD: CodeDeploy, S3, CodeBuild, CodePipeline
# ------------------------------------------------------------------------------
echo "🔄 Generando pipeline-definition con envsubst..."
export BRANCH  # para que la tpl pueda usarlo
envsubst < infra/pipeline-definition.json.tpl > infra/pipeline-ready.json

aws deploy create-application \
  --application-name "${CD_APP_NAME}" \
  --compute-platform ECS \
  ${AWS_COMMON} || true

aws deploy create-deployment-group \
  --application-name "${CD_APP_NAME}" \
  --deployment-group-name "${CD_DG_NAME}" \
  --service-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/codedeploy-ecs-role" \
  --deployment-config-name CodeDeployDefault.ECSLinear10PercentEvery1Minutes \
  --deployment-style deploymentType=BLUE_GREEN,deploymentOption=WITH_TRAFFIC_CONTROL \
  --ecs-services clusterName="${CLUSTER_NAME}",serviceName="${SERVICE_NAME}" \
  --load-balancer "targetGroupPairInfoList=[{prodTrafficRoute={listenerArns=[\"${LISTENER_ARN}\"]},testTrafficRoute={listenerArns=[\"${TEST_LISTENER_ARN}\"]},targetGroups=[{name=${TG_BLUE_NAME}},{name=${TG_GREEN_NAME}}]}]" \
  --blue-green-deployment-configuration file://infra/bg-config.json \
  ${AWS_COMMON} || true

aws s3 mb "s3://${S3_BUCKET}" ${AWS_COMMON} || true

for phase in test build; do
  ENV_OPTS="type=LINUX_CONTAINER,computeType=BUILD_GENERAL1_SMALL,image=aws/codebuild/standard:7.0"
  # sólo habilitamos privilegedMode en el build
  if [[ "$phase" == "build" ]]; then
    ENV_OPTS+=",privilegedMode=true"
  fi

  aws codebuild create-project \
    --name "${phase}-${REPO_NAME}" \
    --source type=CODEPIPELINE,buildspec=buildspec-${phase}.yml \
    --artifacts type=CODEPIPELINE \
    --environment $ENV_OPTS \
    --service-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/codebuild-blacklist-role" \
    ${AWS_COMMON} || true
done

echo "🔄 Asegurando CodePipeline..."

if aws codepipeline get-pipeline --name "pipeline-${REPO_NAME}" ${AWS_COMMON} >/dev/null 2>&1; then
  echo "🔄 Actualizando CodePipeline..."
  aws codepipeline update-pipeline --cli-input-json file://infra/pipeline-ready.json ${AWS_COMMON}
else
  echo "🔧 Creando CodePipeline..."
  aws codepipeline create-pipeline --cli-input-json file://infra/pipeline-ready.json ${AWS_COMMON}
fi

echo "🔄 Generando webhook-definition con envsubst..."

envsubst < infra/webhook-definition.json.tpl > infra/webhook-definition.json

if aws codepipeline list-webhooks ${AWS_COMMON} \
     --query "webhooks[?name=='${WEBHOOK_NAME}']" --output text | grep -q .; then
  echo "🔄 Actualizando webhook..."
  aws codepipeline update-webhook \
    --name "${WEBHOOK_NAME}" \
    --cli-input-json file://infra/webhook-definition.json \
    ${AWS_COMMON}
else
  echo "🔧 Creando webhook..."
  aws codepipeline put-webhook \
    --cli-input-json file://infra/webhook-definition.json \
    ${AWS_COMMON}
fi

echo "✅ Despliegue completo."
set +a
