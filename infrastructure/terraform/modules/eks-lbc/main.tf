# IRSA role for the AWS Load Balancer Controller.
#
# This is the canonical IRSA pattern: an IAM role whose trust policy only
# accepts a specific Kubernetes ServiceAccount, verified via the cluster's
# OIDC provider. The controller's pod assumes this role — no static keys.

variable "environment" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string } # e.g. https://oidc.eks.eu-west-2...

# The IAM permissions the controller needs (official AWS policy, vendored).
resource "aws_iam_policy" "lbc" {
  name   = "${var.environment}-aws-lbc-policy"
  policy = file("${path.module}/iam_policy.json")
}

locals {
  # Strip the https:// prefix — IAM condition keys use the bare hostname/path.
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}

resource "aws_iam_role" "lbc" {
  name = "${var.environment}-aws-lbc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Only THIS service account in THIS namespace may assume the role.
          "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

output "role_arn" {
  value = aws_iam_role.lbc.arn
}
