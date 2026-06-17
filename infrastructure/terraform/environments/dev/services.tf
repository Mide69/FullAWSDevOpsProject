# Backing AWS resources + IRSA roles for claim-, case-, and document-service.
# All three share the single RDS instance (separate tables); document-service
# additionally uses S3, claim-service additionally uses SQS.

# ---------------------------------------------------------------------------
# claim-service — RDS + an SQS queue it publishes to on claim submission.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "claims" {
  name                       = "dev-govplatform-claims"
  message_retention_seconds  = 345600 # 4 days
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true # encryption at rest
  tags                       = { Service = "claim-service" }
}

data "aws_iam_policy_document" "claim_service" {
  statement {
    sid       = "ReadDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.rds.master_user_secret_arn]
  }
  statement {
    sid       = "PublishClaims"
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.claims.arn]
  }
}

module "claim_service_irsa" {
  source            = "../../modules/irsa"
  name              = "dev-claim-service"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "default"
  service_account   = "claim-service"
  policy_json       = data.aws_iam_policy_document.claim_service.json
}

# ---------------------------------------------------------------------------
# case-service — RDS only. Internal-only at the network layer (no public
# Ingress); proves segmentation. IAM just needs the DB secret.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "case_service" {
  statement {
    sid       = "ReadDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.rds.master_user_secret_arn]
  }
}

module "case_service_irsa" {
  source            = "../../modules/irsa"
  name              = "dev-case-service"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "default"
  service_account   = "case-service"
  policy_json       = data.aws_iam_policy_document.case_service.json
}

# ---------------------------------------------------------------------------
# document-service — S3 pre-signed uploads. No DB; just its own bucket.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "documents" {
  bucket = "dev-govplatform-documents-445358171352"
  tags   = { Service = "document-service" }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

data "aws_iam_policy_document" "document_service" {
  statement {
    sid       = "DocumentBucketAccess"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
  }
}

module "document_service_irsa" {
  source            = "../../modules/irsa"
  name              = "dev-document-service"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "default"
  service_account   = "document-service"
  policy_json       = data.aws_iam_policy_document.document_service.json
}

# ---------------------------------------------------------------------------
# Outputs the deploy scripts read to build each service's ConfigMap.
# ---------------------------------------------------------------------------
output "claims_queue_url" { value = aws_sqs_queue.claims.url }
output "documents_bucket" { value = aws_s3_bucket.documents.bucket }
output "claim_service_role_arn" { value = module.claim_service_irsa.role_arn }
output "case_service_role_arn" { value = module.case_service_irsa.role_arn }
output "document_service_role_arn" { value = module.document_service_irsa.role_arn }
