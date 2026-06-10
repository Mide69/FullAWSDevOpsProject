#!/usr/bin/env bash
# setup-codecommit.sh - Bootstrap CodeCommit repo with branch policies
# Demonstrates Linux scripting + AWS CLI + CodeCommit for interview
set -euo pipefail

REPO_NAME="${1:-full-aws-devops-app}"
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Create CodeCommit repository
log "Creating CodeCommit repository: $REPO_NAME"
aws codecommit create-repository \
  --repository-name "$REPO_NAME" \
  --repository-description "Full AWS DevOps demo application" \
  --tags Project=FullAWSDevOps,ManagedBy=Script \
  --region "$REGION" 2>/dev/null || log "Repository already exists"

REPO_URL="https://git-codecommit.${REGION}.amazonaws.com/v1/repos/${REPO_NAME}"
log "Repository URL: $REPO_URL"

# Configure Git credential helper for CodeCommit
log "Configuring Git credential helper..."
git config --global credential.helper \
  "!aws codecommit credential-helper \$@"
git config --global credential.UseHttpPath true

# Clone and set up initial commit if empty
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if aws codecommit get-branch \
    --repository-name "$REPO_NAME" \
    --branch-name main \
    --region "$REGION" 2>/dev/null; then
  log "Repository already has commits"
else
  log "Pushing initial commit..."
  git clone "$REPO_URL" "$TEMP_DIR/repo"
  cp -r . "$TEMP_DIR/repo/" 2>/dev/null || true
  cd "$TEMP_DIR/repo"
  git add -A
  git commit -m "Initial commit: Full AWS DevOps Project"
  git push origin HEAD:main
fi

# Create approval rule template for PRs requiring 2 reviewers
log "Creating approval rule template..."
aws codecommit create-approval-rule-template \
  --approval-rule-template-name "RequireTwoReviewers" \
  --approval-rule-template-description "Requires 2 approvals before merging" \
  --approval-rule-template-content '{
    "Version": "2018-11-08",
    "DestinationReferences": ["refs/heads/main", "refs/heads/release/*"],
    "Statements": [{
      "Type": "Approvers",
      "NumberOfApprovalsNeeded": 2,
      "ApprovalPoolMembers": ["arn:aws:sts::'"$ACCOUNT_ID"':assumed-role/DevOpsEngineer/*"]
    }]
  }' \
  --region "$REGION" 2>/dev/null || log "Approval rule template already exists"

# Associate template with repo
aws codecommit associate-approval-rule-template-with-repository \
  --approval-rule-template-name "RequireTwoReviewers" \
  --repository-name "$REPO_NAME" \
  --region "$REGION" 2>/dev/null || true

log "CodeCommit setup complete!"
log "Clone URL: $REPO_URL"
