module "rds" {
  source = "../../modules/rds"

  environment              = "dev"
  vpc_id                   = module.vpc.vpc_id
  data_subnet_ids          = module.vpc.data_subnet_ids
  source_security_group_id = module.eks.cluster_security_group_id
  multi_az                 = false # dev cost saver
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "db_secret_arn" {
  value = module.rds.master_user_secret_arn
}
