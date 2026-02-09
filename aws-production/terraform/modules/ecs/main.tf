###############################################################################
# ECS Module – Main
#
# Creates an ECS Fargate cluster with:
#   - Container Insights enabled
#   - FARGATE and FARGATE_SPOT capacity providers
#   - Cloud Map private DNS namespace for service discovery
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ECS Cluster with Fargate capacity providers
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = concat(["FARGATE", "FARGATE_SPOT"], var.additional_capacity_providers)

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# Cloud Map namespace for service discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = var.service_discovery_domain
  description = "Service discovery for ${var.name_prefix}"
  vpc         = var.vpc_id

  tags = var.tags
}
