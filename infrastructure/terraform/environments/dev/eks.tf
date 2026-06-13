module "eks" {
  source = "../../modules/eks"

  environment        = "dev"
  private_subnet_ids = module.vpc.private_subnet_ids

  # Cost: SPOT nodes ~70% off; control plane is $0.10/hr regardless —
  # destroy the stack at the end of each working session.
  node_capacity_type = "SPOT"
  node_desired_size  = 2
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}
