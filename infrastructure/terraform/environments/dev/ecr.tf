module "ecr" {
  source = "../../modules/ecr"

  environment   = "dev"
  service_names = ["user-service"]
  # claim-service, case-service, document-service join this list
  # as we build them — one line each.
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}
