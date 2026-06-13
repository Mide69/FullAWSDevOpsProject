variable "environment" {
  type = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.33"
}

variable "private_subnet_ids" {
  description = "Subnets for the cluster and nodes (private tier)"
  type        = list(string)
}

variable "node_instance_types" {
  description = "Instance types for the worker node group"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_capacity_type" {
  description = "SPOT (cheap, reclaimable) or ON_DEMAND (stable, prod)"
  type        = string
  default     = "SPOT"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}
