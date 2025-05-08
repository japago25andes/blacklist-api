#!/usr/bin/env bash
set -euo pipefail

declare -A TRUST_FILES=(
  [ecsTaskExecutionRole]=ecs-trust-policy.json
  [codebuild-blacklist-role]=codebuild-trust.json
  [codepipeline-blacklist-role]=codepipeline-trust.json
  [codedeploy-ecs-role]=codedeploy-trust.json
)

declare -A POLICY_LISTS=(
  [ecsTaskExecutionRole]="\
arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
arn:aws:iam::aws:policy/AmazonElasticLoadBalancingReadOnly"
  [codebuild-blacklist-role]="\
arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser \
arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
  [codepipeline-blacklist-role]="\
arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess \
arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess \
arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser \
arn:aws:iam::aws:policy/AmazonECS_FullAccess \
arn:aws:iam::aws:policy/AmazonElasticLoadBalancingReadOnly"
  [codedeploy-ecs-role]="\
arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS \
arn:aws:iam::aws:policy/AmazonElasticLoadBalancingReadOnly"
)

for role in "${!TRUST_FILES[@]}"; do
  tf="${TRUST_FILES[$role]}"
  echo "⏳ Creando/actualizando rol $role..."
  aws iam create-role \
    --role-name "$role" \
    --assume-role-policy-document file://"$tf" \
    --output text \
  || echo "  → ya existe: $role"

  for policy in ${POLICY_LISTS[$role]}; do
    echo "    🔗 Atachando $policy a $role"
    aws iam attach-role-policy \
      --role-name "$role" \
      --policy-arn "$policy" \
      --output text \
    || echo "      → ya attachado"
  done
done
