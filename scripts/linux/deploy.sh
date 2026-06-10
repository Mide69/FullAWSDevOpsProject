#!/usr/bin/env bash
# deploy.sh - Manual deployment script with pre/post checks
# Usage: ./scripts/linux/deploy.sh <environment> <image-tag>
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <dev|staging|prod> <image-tag>}"
IMAGE_TAG="${2:?Usage: $0 <dev|staging|prod> <image-tag>}"
APP_NAME="full-aws-devops-app"
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

# Validate environment
[[ "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]] || error "Invalid environment: $ENVIRONMENT"

# Production safety gate
if [[ "$ENVIRONMENT" == "prod" ]]; then
  read -r -p "Deploying to PRODUCTION. Type 'yes' to confirm: " confirm
  [[ "$confirm" == "yes" ]] || error "Aborted"
fi

log "Starting deployment: $APP_NAME:$IMAGE_TAG to $ENVIRONMENT"

# Verify image exists in ECR
ECR_REPO="${APP_NAME}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

log "Verifying image in ECR..."
aws ecr describe-images \
  --repository-name "$ECR_REPO" \
  --image-ids "imageTag=${IMAGE_TAG}" \
  --region "$REGION" > /dev/null || error "Image $IMAGE_TAG not found in ECR"

# Get current task definition
TASK_FAMILY="${APP_NAME}-${ENVIRONMENT}"
log "Fetching current task definition: $TASK_FAMILY"
CURRENT_TASK=$(aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" \
  --query 'taskDefinition' \
  --output json \
  --region "$REGION")

# Update image in task definition
log "Registering new task definition..."
NEW_TASK=$(echo "$CURRENT_TASK" | jq \
  --arg IMAGE "${ECR_URI}:${IMAGE_TAG}" \
  '.containerDefinitions[0].image = $IMAGE |
   del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)')

NEW_TASK_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text \
  --region "$REGION")
log "New task definition: $NEW_TASK_ARN"

# Trigger CodeDeploy Blue/Green deployment
APP_NAME_CD="${APP_NAME}-codedeploy"
DG_NAME="${APP_NAME}-${ENVIRONMENT}-dg"

log "Creating CodeDeploy deployment..."
DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name "$APP_NAME_CD" \
  --deployment-group-name "$DG_NAME" \
  --revision "{
    \"revisionType\": \"AppSpecContent\",
    \"appSpecContent\": {
      \"content\": \"{\\\"version\\\":0,\\\"Resources\\\":[{\\\"TargetService\\\":{\\\"Type\\\":\\\"AWS::ECS::Service\\\",\\\"Properties\\\":{\\\"TaskDefinition\\\":\\\"${NEW_TASK_ARN}\\\",\\\"LoadBalancerInfo\\\":{\\\"ContainerName\\\":\\\"app\\\",\\\"ContainerPort\\\":3000}}}}]}\"
    }
  }" \
  --query 'deploymentId' \
  --output text \
  --region "$REGION")

log "Deployment created: $DEPLOYMENT_ID"
log "Monitoring deployment status..."

# Poll for deployment completion
MAX_WAIT=600
ELAPSED=0
while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  STATUS=$(aws deploy get-deployment \
    --deployment-id "$DEPLOYMENT_ID" \
    --query 'deploymentInfo.status' \
    --output text \
    --region "$REGION")

  log "Status: $STATUS (${ELAPSED}s elapsed)"

  case "$STATUS" in
    Succeeded)
      log "Deployment SUCCEEDED"
      exit 0 ;;
    Failed|Stopped)
      error "Deployment $STATUS. Check CodeDeploy console." ;;
    *)
      sleep 15
      ELAPSED=$((ELAPSED + 15)) ;;
  esac
done

error "Deployment timed out after ${MAX_WAIT}s"
