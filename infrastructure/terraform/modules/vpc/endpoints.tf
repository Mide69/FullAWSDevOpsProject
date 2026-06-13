# VPC Endpoints — private paths to AWS services that skip the internet/NAT.
#
# Gateway endpoints (S3, DynamoDB): FREE — just route table entries. Always on.
# Interface endpoints (everything else): ~£7/month EACH — an ENI per subnet
# with a private DNS name. Enabled per-environment via var.interface_endpoints.

data "aws_region" "current" {}

# --- S3 gateway endpoint (free, always) -------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.data.id],
  )

  tags = { Name = "${var.environment}-s3-endpoint" }
}

# --- Interface endpoints (paid, opt-in) --------------------------------------
# Allows HTTPS from anywhere inside the VPC to the endpoint ENIs.
resource "aws_security_group" "endpoints" {
  count       = length(var.interface_endpoints) > 0 ? 1 : 0
  name        = "${var.environment}-vpc-endpoints"
  description = "HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = { Name = "${var.environment}-vpc-endpoints-sg" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.environment}-${each.value}-endpoint" }
}
