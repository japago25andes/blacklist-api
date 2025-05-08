#!/usr/bin/env bash
set -euo pipefail

# Nombre de tu target group “green”
TG_NAME="blacklist-tg-green"
AWS_REGION="us-east-1"

# 1) Recuperar dinámicamente el ARN del target group
TG_ARN=$(aws elbv2 describe-target-groups \
  --names "$TG_NAME" \
  --region "$AWS_REGION" \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text)

echo "🔗 Usando Target Group ARN: $TG_ARN"

# 2) Esperar hasta que al menos 1 IP esté healthy
echo "👀 Verificando estado GREEN en target group '$TG_NAME'..."
until [ "$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" \
    --output text)" -ge 1 ]; do
  echo "  aún no healthy; esperando 10s..."
  sleep 10
done

echo "✅ Al menos un target está healthy en '$TG_NAME'"
exit 0
