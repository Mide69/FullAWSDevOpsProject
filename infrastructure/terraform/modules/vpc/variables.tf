variable "environment" {
  description = "Environment name, used in resource names and tags (e.g. dev, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB tier), one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS tier), one per AZ"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, dev). false = one NAT per AZ (HA, prod)."
  type        = bool
  default     = false
}

variable "interface_endpoints" {
  description = "Interface endpoint services to create (~£7/mo each), e.g. [\"ecr.api\", \"ecr.dkr\", \"secretsmanager\", \"logs\", \"sts\"]. Empty = none (traffic uses NAT)."
  type        = list(string)
  default     = []
}

variable "data_subnet_cidrs" {
  description = "CIDR blocks for data subnets (RDS tier), one per AZ"
  type        = list(string)
}
