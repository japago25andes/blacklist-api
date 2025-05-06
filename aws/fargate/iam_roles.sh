aws iam create-role \
--role-name ecsTaskExecutionRole \
--assume-role-policy-document file://ecs-trust-policy.json

aws iam attach-role-policy \
--role-name ecsTaskExecutionRole \
--policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam create-role \
--role-name codebuild-blacklist-role \
--assume-role-policy-document file://codebuild-trust.json

# Permite acceso a ECR
aws iam attach-role-policy \
--role-name codebuild-blacklist-role \
--policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# Permite logs en CloudWatch
aws iam attach-role-policy \
--role-name codebuild-blacklist-role \
--policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# Permite operar CodeBuild y S3 artefactos
aws iam attach-role-policy \
--role-name codebuild-blacklist-role \
--policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess

aws iam create-role \
--role-name codepipeline-blacklist-role \
--assume-role-policy-document file://codepipeline-trust.json

# 1. AWSCodePipeline_FullAccess
aws iam attach-role-policy \
  --role-name codepipeline-blacklist-role \
  --policy-arn arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess

# 2. AWSCodeBuildDeveloperAccess
aws iam attach-role-policy \
  --role-name codepipeline-blacklist-role \
  --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess

# 3. AmazonEC2ContainerRegistryPowerUser
aws iam attach-role-policy \
  --role-name codepipeline-blacklist-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# 4. AmazonECS_FullAccess
aws iam attach-role-policy \
  --role-name codepipeline-blacklist-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

aws iam create-role \
--role-name codedeploy-ecs-role \
--assume-role-policy-document file://codedeploy-trust.json

aws iam attach-role-policy \
  --role-name codedeploy-ecs-role \
  --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS

aws sts get-caller-identity --query Arn --output text

## ROOT por defecto ya tiene todos los permisos (NO SERIA NECESARIO)
aws iam put-user-policy \
--user-name root \
--policy-name AllowPassRoles \
--policy-document file://pass-all-roles.json