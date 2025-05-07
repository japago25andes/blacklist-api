export AWS_ACCOUNT_ID=774305595347
export AWS_REGION=us-east-1
export REPO_NAME=blacklist-api
export REPO_OWNER=japago25andes
export BRANCH=main
export CLUSTER_NAME=blacklist-api-cluster
export SERVICE_NAME=blacklist-api-service-fargate
export TASK_FAMILY=blacklist-task-definition
export DB_INSTANCE_ID=blacklist-db
export DB_USERNAME=blacklist_user
export DB_PASSWORD=blacklist_password
export DB_NAME=blacklist_db
export VPC_ID=vpc-0ea87756eab16d187
export LOG_GROUP=blacklist-api-logs

export SUBNETS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query "Subnets[].SubnetId" \
  --output text \
  --region $AWS_REGION)
echo "Subnets detectadas: $SUBNETS"

export S3_BUCKET=blacklist-pipeline-artifacts-$AWS_ACCOUNT_ID
export GITHUB_SECRET_NAME=github-token-blacklist-api

# ------------------------ Create security groups for DB ----------------------------------------------

SG_RDS=$(aws ec2 create-security-group \
  --group-name postgres-bs-sg \
  --description "RDS Postgres Free Tier" \
  --vpc-id $VPC_ID \
  --query "GroupId" --output text \
  --region $AWS_REGION)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_RDS \
  --protocol tcp --port 5432 --cidr 0.0.0.0/0 \
  --region $AWS_REGION


# ----------------------------- Create DB --------------------------------------------------

aws rds create-db-instance \
  --db-instance-identifier $DB_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15 \
  --allocated-storage 20 \
  --master-username $DB_USERNAME \
  --master-user-password $DB_PASSWORD \
  --db-name $DB_NAME \
  --vpc-security-group-ids $SG_RDS \
  --publicly-accessible \
  --no-multi-az \
  --storage-type gp2 \
  --backup-retention-period 0 \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $DB_INSTANCE_ID \
  --region $AWS_REGION

export DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE_ID \
  --query "DBInstances[0].Endpoint.Address" \
  --output text \
  --region $AWS_REGION)

# blacklist-db.cwfgue6aucq3.us-east-1.rds.amazonaws.com
echo "Postgres endpoint: $DB_ENDPOINT"


# ----------------------------- Create DB connection URL ENV ---------------------------------------
export AUTH_TOKEN="mi_token_super_secreto"
export DATABASE_URL="postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_ENDPOINT:5432/$DB_NAME"


# ----------------------------- Create load balancer --------------------------------------------

SG_ALB=$(aws ec2 create-security-group \
  --group-name alb-bs-sg \
  --description "SG ALB para blacklist-api" \
  --vpc-id $VPC_ID \
  --query "GroupId" --output text \
  --region $AWS_REGION)

# Permite HTTP 80 desde Internet
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ALB \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  --region $AWS_REGION

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name blacklist-alb \
  --subnets $SUBNETS \
  --security-groups $SG_ALB \
  --scheme internet-facing \
  --type application \
  --query "LoadBalancers[0].LoadBalancerArn" --output text \
  --region $AWS_REGION)

TG_ARN=$(aws elbv2 create-target-group \
  --name blacklist-tg \
  --protocol HTTP \
  --port 5000 \
  --vpc-id $VPC_ID \
  --health-check-protocol HTTP \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 3 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 5 \
  --target-type ip \
  --query "TargetGroups[0].TargetGroupArn" --output text \
  --region $AWS_REGION)

aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $AWS_REGION



# ----------------------------- Create log group --------------------------------------------
aws logs create-log-group --log-group-name $LOG_GROUP --region $AWS_REGION



# ----------------------------- Create ECR repository --------------------------------------------
aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -t $REPO_NAME:latest .
docker tag $REPO_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest


## ----------------------------- SG for FARGATE --------------------------------------------

SG_TASK=$(aws ec2 create-security-group \
  --group-name task-bs-sg \
  --description "Fargate SG para blacklist-api" \
  --vpc-id $VPC_ID \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_TASK --protocol tcp --port 5000 \
  --source-group $SG_ALB


## ----------------------------- Create FARGATE cluster --------------------------------------------

aws ecs create-cluster \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION

# ----------------------------- Create and REGISTER FARGATE task --------------------------------------------

aws ecs register-task-definition \
  --family $TASK_FAMILY \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 512 \
  --memory 1024 \
  --execution-role-arn arn:aws:iam::774305595347:role/ecsTaskExecutionRole \
  --container-definitions "$(cat <<EOF
[{
  "name":"blacklist-api",
  "image":"$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest",
  "portMappings":[{"containerPort":5000,"protocol":"tcp"}],
  "environment":[
    {"name":"DATABASE_URL","value":"postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_ENDPOINT:5432/$DB_NAME"},
    {"name":"AUTH_TOKEN","value":"$AUTH_TOKEN"}
  ],
  "logConfiguration":{
    "logDriver":"awslogs",
    "options":{
      "awslogs-group":"$LOG_GROUP",
      "awslogs-region":"$AWS_REGION",
      "awslogs-stream-prefix":"ecs"
    }
  }
}]
EOF
)" \
  --region $AWS_REGION


# ----------------------------- Create FARGATE service --------------------------------------------

# Convert subnets to a comma-separated string
echo "Subnets detected: $SUBNETS"
SUBNET_CSV=$(echo $SUBNETS | tr ' ' ',')

# Create the ECS service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_FAMILY \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_CSV],securityGroups=[$SG_TASK],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=blacklist-api,containerPort=5000" \
  --health-check-grace-period-seconds 60 \
  --region $AWS_REGION


#-----------------------verify subnets AND route table-----------------------------
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters Name=attachment.vpc-id,Values=$VPC_ID \
  --query "InternetGateways[0].InternetGatewayId" \
  --output text \
  --region $AWS_REGION)

RTB_ID=$(aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=$VPC_ID Name=association.main,Values=true \
  --query "RouteTables[0].RouteTableId" \
  --output text \
  --region $AWS_REGION)

aws ec2 describe-route-tables \
  --route-table-ids $RTB_ID \
  --query "RouteTables[0].Associations" \
  --output table \
  --region $AWS_REGION

for subnet in $SUBNETS; do
  aws ec2 associate-route-table \
    --route-table-id $RTB_ID \
    --subnet-id $subnet \
    --region $AWS_REGION
done

# ------------------- CODE PIPELINE & CODE DEPLOY --------------------------------

aws codebuild import-source-credentials \
  --server-type GITHUB \
  --auth-type PERSONAL_ACCESS_TOKEN \
  --token <PAT> \
  --region $AWS_REGION

# preparar el bucket para artefactos
aws s3 mb s3://blacklist-pipeline-artifacts-$AWS_ACCOUNT_ID --region $AWS_REGION


# crear el proyecto de codebuild
aws codebuild create-project \
  --name build-blacklist-api \
  --description "Build y test para blacklist-api vía CodePipeline" \
  --source type=CODEPIPELINE \
  --artifacts type=CODEPIPELINE \
  --environment type=LINUX_CONTAINER,computeType=BUILD_GENERAL1_SMALL,image=aws/codebuild/standard:7.0,privilegedMode=true \
  --service-role arn:aws:iam::774305595347:role/codebuild-blacklist-role \
  --region $AWS_REGION