#!/usr/bin/env bash
# Deploy user-service to EKS.
#
# Mirrors what a CI pipeline would do:
#   1. Read the changing infra values from Terraform outputs.
#   2. Create/update the db-config ConfigMap from them.
#   3. Apply the Kubernetes manifests.
#
# Usage: ./scripts/deploy-user-service.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform/environments/dev"

echo "==> Reading Terraform outputs"
DB_HOST=$(terraform -chdir="$TF_DIR" output -raw db_endpoint)
DB_SECRET_ARN=$(terraform -chdir="$TF_DIR" output -raw db_secret_arn)

echo "    DB_HOST=$DB_HOST"
echo "    DB_SECRET_ARN=$DB_SECRET_ARN"

echo "==> Writing db-config ConfigMap"
kubectl create configmap db-config \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="5432" \
  --from-literal=DB_NAME="govplatform" \
  --from-literal=DB_SECRET_ARN="$DB_SECRET_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying manifests"
kubectl apply -f "$REPO_ROOT/k8s/user-service/"

echo "==> Restarting to pick up new config"
kubectl rollout restart deployment/user-service
kubectl rollout status deployment/user-service --timeout=120s

echo "✅ Deployed."
