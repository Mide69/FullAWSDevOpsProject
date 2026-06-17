module "ecr" {
  source = "../../modules/ecr"

  environment   = "dev"
  service_names = ["user-service", "claim-service", "case-service", "document-service"]
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}
