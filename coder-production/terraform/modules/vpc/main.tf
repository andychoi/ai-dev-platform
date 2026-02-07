################################################################################
# VPC
################################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

################################################################################
# Subnets
################################################################################

# Public subnets — NAT Gateway only (no public ALB; all access via VPN)
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index) # .0.0/24, .1.0/24
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
  })
}

# Private app subnets — ECS Fargate tasks, internal ALB
resource "aws_subnet" "private_app" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # .10.0/24, .11.0/24
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-${var.availability_zones[count.index]}"
  })
}

# Private data subnets — RDS, ElastiCache
resource "aws_subnet" "private_data" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20) # .20.0/24, .21.0/24
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-data-${var.availability_zones[count.index]}"
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

################################################################################
# NAT Gateway (single AZ for cost)
################################################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

################################################################################
# Route Tables
################################################################################

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private app route table
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-app"
  })
}

resource "aws_route" "private_app_nat" {
  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private_app" {
  count = 2

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Private data route table
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-data"
  })
}

resource "aws_route" "private_data_nat" {
  route_table_id         = aws_route_table.private_data.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private_data" {
  count = 2

  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}

################################################################################
# VPC Endpoints
################################################################################

# Security group for interface VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "Allow HTTPS from VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpce-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# S3 gateway endpoint (free, no per-hour charge)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_data.id,
  ]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpce-s3"
  })
}

# Interface endpoints — placed in private app subnets
locals {
  interface_endpoints = {
    ecr_api             = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
    ecr_dkr             = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
    secretsmanager      = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
    logs                = "com.amazonaws.${data.aws_region.current.name}.logs"
    sts                 = "com.amazonaws.${data.aws_region.current.name}.sts"
    bedrock_runtime     = "com.amazonaws.${data.aws_region.current.name}.bedrock-runtime"
    ecs                 = "com.amazonaws.${data.aws_region.current.name}.ecs"
    ecs_agent           = "com.amazonaws.${data.aws_region.current.name}.ecs-agent"
    ecs_telemetry       = "com.amazonaws.${data.aws_region.current.name}.ecs-telemetry"
    elasticfilesystem   = "com.amazonaws.${data.aws_region.current.name}.elasticfilesystem"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private_app[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpce-${each.key}"
  })
}

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}
