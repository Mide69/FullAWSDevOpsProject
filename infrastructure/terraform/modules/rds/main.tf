# RDS PostgreSQL — in the data subnets, reachable only from the EKS cluster.
# Master password is created and rotated by RDS in Secrets Manager; it never
# touches Terraform code or state.

variable "environment" { type = string }
variable "data_subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "source_security_group_id" {
  description = "SG allowed to reach the DB (the EKS cluster SG)"
  type        = string
}
variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "multi_az" {
  type    = bool
  default = false # dev: single-AZ. prod: true (one-line change).
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db"
  subnet_ids = var.data_subnet_ids
  tags       = { Name = "${var.environment}-db-subnet-group" }
}

resource "aws_security_group" "db" {
  name        = "${var.environment}-rds"
  description = "Postgres access from the EKS cluster only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.source_security_group_id]
  }

  tags = { Name = "${var.environment}-rds-sg" }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-govplatform"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true # KMS encryption at rest (default aws/rds key)

  db_name  = "govplatform"
  username = "dbadmin"
  # RDS creates + rotates the master password in Secrets Manager:
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = var.multi_az

  backup_retention_period = 7
  skip_final_snapshot     = true # dev: don't snapshot on destroy. prod: false.
  deletion_protection     = false # dev only

  tags = { Name = "${var.environment}-govplatform-db" }
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

# ARN of the Secrets Manager secret RDS manages — the app's IRSA role
# will be granted read access to exactly this.
output "master_user_secret_arn" {
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}
