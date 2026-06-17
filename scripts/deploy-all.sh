#!/usr/bin/env bash
# Deploy the ENTIRE GovPlatform: build+push all 4 service images, generate
# config from Terraform outputs, and apply all Kubernetes manifests.
#
# What a real CI/CD pipeline does — here as one reproducible script.
# Usage: ./scripts/deploy-all.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform/environments/dev"
ECR=445358171352.dkr.ecr.eu-west-2.amazonaws.com
REGION=eu-west-2
PROFILE=govplatform-dev
SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD)

echo "==> Reading Terraform outputs"
DB_HOST=$(terraform -chdir="$TF_DIR" output -raw db_endpoint)
DB_SECRET_ARN=$(terraform -chdir="$TF_DIR" output -raw db_secret_arn)
CLAIMS_QUEUE_URL=$(terraform -chdir="$TF_DIR" output -raw claims_queue_url)
DOCUMENTS_BUCKET=$(terraform -chdir="$TF_DIR" output -raw documents_bucket)
WAF_ARN=$(terraform -chdir="$TF_DIR" output -raw waf_acl_arn)

echo "==> Docker login to ECR"
aws ecr get-login-password --region $REGION --profile $PROFILE | docker login --username AWS --password-stdin $ECR

build_push () { # $1 = service name, $2 = build context path
  echo "==> Building $1 ($SHA)"
  docker build -f "$REPO_ROOT/containers/Dockerfile" --build-arg SERVICE_PATH="$2" \
    -t "$ECR/govplatform/$1:$SHA" "$REPO_ROOT"
  docker push "$ECR/govplatform/$1:$SHA"
}
build_push user-service     app
build_push claim-service    services/claim-service
build_push case-service     services/case-service
build_push document-service services/document-service

echo "==> Config (ConfigMaps from Terraform outputs)"
kubectl create configmap db-config \
  --from-literal=DB_HOST="$DB_HOST" --from-literal=DB_PORT="5432" \
  --from-literal=DB_NAME="govplatform" --from-literal=DB_SECRET_ARN="$DB_SECRET_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap claim-config \
  --from-literal=CLAIMS_QUEUE_URL="$CLAIMS_QUEUE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap document-config \
  --from-literal=DOCUMENTS_BUCKET="$DOCUMENTS_BUCKET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying manifests (image tag $SHA)"
for f in \
  k8s/user-service/serviceaccount.yaml k8s/user-service/deployment.yaml k8s/user-service/service.yaml \
  k8s/claim-service/claim-service.yaml \
  k8s/case-service/case-service.yaml \
  k8s/document-service/document-service.yaml ; do
  sed "s/IMAGE_TAG/$SHA/g" "$REPO_ROOT/$f" | kubectl apply -f -
done

echo "==> Applying shared Ingress (WAF attached)"
sed "s|WAF_ACL_ARN|$WAF_ARN|g" "$REPO_ROOT/k8s/platform/ingress.yaml" | kubectl apply -f -

echo "==> Waiting for rollouts"
for d in user-service claim-service case-service document-service; do
  kubectl rollout status deployment/$d --timeout=180s
done

echo "✅ All services deployed at image tag $SHA"
echo "   ALB URL:"
kubectl get ingress govplatform -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
