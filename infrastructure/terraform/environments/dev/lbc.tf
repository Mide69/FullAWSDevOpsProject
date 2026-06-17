module "eks_lbc" {
  source = "../../modules/eks-lbc"

  environment       = "dev"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

output "lbc_role_arn" {
  value = module.eks_lbc.role_arn
}
