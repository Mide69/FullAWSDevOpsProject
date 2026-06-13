# ECR — one repository per service.
#
# immutable tags  : a tag, once pushed, can never point to a different image.
#                   What you tested is what you deploy. Non-negotiable.
# scan on push    : every image is checked against known CVEs as it arrives.
# lifecycle policy: keep the newest 20 images, expire the rest — otherwise
#                   a busy pipeline grows storage costs forever.

variable "environment" {
  type = string
}

variable "service_names" {
  description = "One ECR repository is created per service name"
  type        = list(string)
}

resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  name                 = "govplatform/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Service = each.value }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the newest 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}
