# Permission for the user-service pod to read ONLY the RDS-managed DB secret.
data "aws_iam_policy_document" "user_service" {
  statement {
    sid       = "ReadDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.rds.master_user_secret_arn]
  }
}

module "user_service_irsa" {
  source = "../../modules/irsa"

  name              = "dev-user-service"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "default"
  service_account   = "user-service"
  policy_json       = data.aws_iam_policy_document.user_service.json
}

output "user_service_role_arn" {
  value = module.user_service_irsa.role_arn
}
