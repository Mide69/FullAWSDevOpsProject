terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "devops-terraform-state-ACCOUNT_ID"
    key            = "full-aws-devops/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "alias/terraform-state"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "FullAWSDevOps"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DevOps"
    }
  }
}

module "vpc" {
  source = "./modules/vpc"

  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
}

module "ecr" {
  source = "./modules/ecr"

  repository_name    = var.app_name
  image_tag_mutability = "IMMUTABLE"
  scan_on_push       = true
}

module "ecs" {
  source = "./modules/ecs"

  app_name        = var.app_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnet_ids
  alb_arn         = module.alb.alb_arn
  ecr_repo_url    = module.ecr.repository_url
  task_cpu        = var.task_cpu
  task_memory     = var.task_memory
  desired_count   = var.desired_count
}

module "alb" {
  source = "./modules/alb"

  app_name       = var.app_name
  environment    = var.environment
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnet_ids
  certificate_arn = var.certificate_arn
}

module "rds" {
  source = "./modules/rds"

  app_name        = var.app_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnet_ids
  instance_class  = var.db_instance_class
  engine_version  = "14.9"
}

module "waf" {
  source = "./modules/waf"

  app_name   = var.app_name
  alb_arn    = module.alb.alb_arn
}

module "monitoring" {
  source = "./modules/monitoring"

  app_name          = var.app_name
  environment       = var.environment
  ecs_cluster_name  = module.ecs.cluster_name
  ecs_service_name  = module.ecs.service_name
  alb_arn_suffix    = module.alb.alb_arn_suffix
  alarm_email       = var.alarm_email
}
