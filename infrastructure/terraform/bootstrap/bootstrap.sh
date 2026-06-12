#!/usr/bin/env bash
# =============================================================================
# Terraform State Bootstrap — govplatform-dev (445358171352)
#
# Creates the two resources Terraform needs BEFORE it can manage anything:
#   1. S3 bucket   — stores the state file (versioned, encrypted, private)
#   2. DynamoDB    — state lock table (prevents concurrent applies)
#
# This is the ONLY infrastructure created outside Terraform.
# Run once: ./bootstrap.sh
# =============================================================================
set -euo pipefail

PROFILE="govplatform-dev"
REGION="eu-west-2"
ACCOUNT_ID="445358171352"
BUCKET="govplatform-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="govplatform-tflock"

echo "==> Verifying identity..."
aws sts get-caller-identity --profile "$PROFILE" --query Account --output text | grep -q "$ACCOUNT_ID" \
  || { echo "ERROR: not connected to account $ACCOUNT_ID"; exit 1; }

echo "==> Creating state bucket: $BUCKET"
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  --profile "$PROFILE"

echo "==> Enabling versioning (recover from corrupted/deleted state)"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --profile "$PROFILE"

echo "==> Enabling encryption at rest (SSE-S3)"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --profile "$PROFILE"

echo "==> Blocking ALL public access"
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile "$PROFILE"

echo "==> Creating lock table: $LOCK_TABLE"
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  --profile "$PROFILE"

echo ""
echo "✅ Bootstrap complete. Backend config for Terraform:"
echo ""
echo "  backend \"s3\" {"
echo "    bucket         = \"$BUCKET\""
echo "    key            = \"govplatform/terraform.tfstate\""
echo "    region         = \"$REGION\""
echo "    dynamodb_table = \"$LOCK_TABLE\""
echo "    encrypt        = true"
echo "  }"
