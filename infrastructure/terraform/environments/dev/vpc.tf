# GovPlatform dev network — 3 AZs × 3 tiers (public / private / data)
#
# CIDR plan (10.0.0.0/16 = 65,536 addresses):
#   public:  10.0.0.x – 10.0.2.x   (ALB)
#   private: 10.0.10.x – 10.0.12.x (EKS nodes)
#   data:    10.0.20.x – 10.0.22.x (RDS, ElastiCache)
# Gaps between tiers leave room to grow without renumbering.

module "vpc" {
  source = "../../modules/vpc"

  environment        = "dev"
  single_nat_gateway = true # cost: ~£33/mo vs ~£100/mo. Prod uses one per AZ.
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnet_cidrs    = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
