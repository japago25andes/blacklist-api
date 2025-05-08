#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
ALB_NAME="blacklist-alb"
AWS_REGION="us-east-1"

# 1) Recupera dinámicamente el DNSName del ALB
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names "$ALB_NAME" \
  --region "$AWS_REGION" \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "🔗 Usando ALB DNS: $ALB_DNS"

# 2) Comprueba el endpoint raíz en producción
echo "🔍 Verificando endpoint raíz en producción..."
status=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}/")
if [ "$status" -ne 200 ]; then
  echo "❌ La aplicación respondió HTTP $status en producción" >&2
  exit 1
fi

echo "✅ Producción responde correctamente"
exit 0
