#!/usr/bin/env bash
set -euo pipefail

# Variables (asegúrate de tener AWS_REGION exportado o usar AWS_COMMON)
ALB_NAME="blacklist-alb"
AWS_COMMON="--region ${AWS_REGION:-us-east-1} --output json"

# 1. Recupera dinámicamente el DNSName del ALB
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names "$ALB_NAME" \
  $AWS_COMMON \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "🔗 Usando ALB DNS: $ALB_DNS"

# 2. Smoke test
echo "🚦 Ejecutando smoke-test en /health..."
for i in {1..5}; do
  status_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}/health")
  echo "  intento $i → código HTTP $status_code"
  if [ "$status_code" -eq 200 ]; then
    echo "✅ Smoke-test OK"
    exit 0
  fi
  sleep 5
done

echo "❌ Smoke-test falló tras múltiples intentos" >&2
exit 1
