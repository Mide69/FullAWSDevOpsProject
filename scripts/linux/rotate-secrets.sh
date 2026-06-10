#!/usr/bin/env bash
# rotate-secrets.sh - Rotates Secrets Manager secrets and updates ECS
# Demonstrates Linux scripting + Secrets Manager + ECS for interview
set -euo pipefail

SECRET_ARN="${1:?Usage: $0 <secret-arn>}"
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Initiating rotation for secret: $SECRET_ARN"

# Trigger rotation
aws secretsmanager rotate-secret \
  --secret-id "$SECRET_ARN" \
  --region "$REGION"

# Wait for rotation to complete
log "Waiting for rotation to complete..."
for i in $(seq 1 12); do
  STATUS=$(aws secretsmanager describe-secret \
    --secret-id "$SECRET_ARN" \
    --query 'RotationEnabled' \
    --output text \
    --region "$REGION")

  LAST_ROTATED=$(aws secretsmanager describe-secret \
    --secret-id "$SECRET_ARN" \
    --query 'LastRotatedDate' \
    --output text \
    --region "$REGION")

  log "Rotation status check $i/12 - Last rotated: $LAST_ROTATED"

  if [[ "$STATUS" == "True" ]]; then
    log "Secret rotation completed successfully"
    break
  fi
  sleep 10
done

# Force new ECS deployment to pick up rotated secret
log "Forcing ECS service redeployment to pick up new secret..."
ECS_CLUSTER=$(aws ssm get-parameter \
  --name "/devops/prod/ecs-cluster" \
  --query 'Parameter.Value' \
  --output text \
  --region "$REGION")

ECS_SERVICE=$(aws ssm get-parameter \
  --name "/devops/prod/ecs-service" \
  --query 'Parameter.Value' \
  --output text \
  --region "$REGION")

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --force-new-deployment \
  --region "$REGION"

log "ECS service redeployment triggered. Secret rotation complete."
