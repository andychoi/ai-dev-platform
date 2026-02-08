# -----------------------------------------------------------------------------
# Coder WebIDE Production — Root Module
# AWS deployment: ECS Fargate + managed services
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
    })
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Phase 1: AWS Foundation
# -----------------------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = var.tags
}

module "ecs" {
  source = "./modules/ecs"

  name_prefix              = local.name_prefix
  vpc_id                   = module.vpc.vpc_id
  service_discovery_domain = "${local.name_prefix}.local"
  tags                     = var.tags
}

module "alb" {
  source = "./modules/alb"

  name_prefix     = local.name_prefix
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_app_subnet_ids
  certificate_arn = module.acm.certificate_arn
  vpc_cidr        = var.vpc_cidr
  domain_name     = var.domain_name
  tags            = var.tags

  # Dual-path: direct workspace access via ALB with OIDC authentication
  enable_workspace_direct_access = var.enable_workspace_direct_access
  oidc_issuer_url                = var.oidc_issuer_url
  oidc_client_id                 = var.oidc_alb_client_id
  oidc_client_secret             = var.oidc_alb_client_secret
  oidc_token_endpoint            = var.oidc_token_endpoint
  oidc_authorization_endpoint    = var.oidc_authorization_endpoint
  oidc_user_info_endpoint        = var.oidc_user_info_endpoint
}

module "efs" {
  source = "./modules/efs"

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_app_subnet_ids
  allowed_security_groups = [aws_security_group.ecs_services.id, aws_security_group.ecs_workspaces.id]
  tags                    = var.tags
}

module "rds" {
  source = "./modules/rds"

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_data_subnet_ids
  allowed_security_groups = [aws_security_group.ecs_services.id]
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  max_allocated_storage   = var.rds_max_allocated_storage
  tags                    = var.tags
}

module "elasticache" {
  source = "./modules/elasticache"

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_data_subnet_ids
  allowed_security_groups = [aws_security_group.ecs_services.id]
  node_type               = var.redis_node_type
  tags                    = var.tags
}

module "s3" {
  source = "./modules/s3"

  name_prefix = local.name_prefix
  tags        = var.tags
}

module "acm" {
  source = "./modules/acm"

  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
  tags           = var.tags
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix         = local.name_prefix
  rds_endpoint        = module.rds.endpoint
  rds_master_password = module.rds.master_password
  tags                = var.tags
}

module "iam" {
  source = "./modules/iam"

  name_prefix        = local.name_prefix
  ecs_cluster_arn    = module.ecs.cluster_arn
  efs_file_system_arn = module.efs.file_system_arn
  secrets_arns       = module.secrets.secret_arns
  s3_bucket_arns     = module.s3.bucket_arns
  aws_region         = var.aws_region
  tags               = var.tags
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

# Platform services: Coder, Authentik, LiteLLM, Langfuse, ClickHouse
resource "aws_security_group" "ecs_services" {
  name        = "${local.name_prefix}-ecs-services"
  description = "Security group for ECS platform services (Coder, Authentik, LiteLLM, Langfuse)"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-services"
  })
}

# Inbound: ALB to service ports
resource "aws_vpc_security_group_ingress_rule" "services_from_alb_coder" {
  security_group_id            = aws_security_group.ecs_services.id
  referenced_security_group_id = module.alb.alb_security_group_id
  from_port                    = 7080
  to_port                      = 7080
  ip_protocol                  = "tcp"
  description                  = "ALB to Coder"
}

resource "aws_vpc_security_group_ingress_rule" "services_from_alb_authentik" {
  security_group_id            = aws_security_group.ecs_services.id
  referenced_security_group_id = module.alb.alb_security_group_id
  from_port                    = 9000
  to_port                      = 9000
  ip_protocol                  = "tcp"
  description                  = "ALB to Authentik"
}

resource "aws_vpc_security_group_ingress_rule" "services_from_alb_litellm" {
  security_group_id            = aws_security_group.ecs_services.id
  referenced_security_group_id = module.alb.alb_security_group_id
  from_port                    = 4000
  to_port                      = 4000
  ip_protocol                  = "tcp"
  description                  = "ALB to LiteLLM"
}

resource "aws_vpc_security_group_ingress_rule" "services_from_alb_langfuse" {
  security_group_id            = aws_security_group.ecs_services.id
  referenced_security_group_id = module.alb.alb_security_group_id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
  description                  = "ALB to Langfuse"
}

# Inbound: services can communicate with each other
resource "aws_vpc_security_group_ingress_rule" "services_self" {
  security_group_id            = aws_security_group.ecs_services.id
  referenced_security_group_id = aws_security_group.ecs_services.id
  ip_protocol                  = "-1"
  description                  = "Inter-service communication"
}

# Inbound: workspaces can reach LiteLLM on services SG
resource "aws_vpc_security_group_ingress_rule" "services_from_workspaces_litellm" {
  security_group_id            = aws_security_group.ecs_services.id
  referenced_security_group_id = aws_security_group.ecs_workspaces.id
  from_port                    = 4000
  to_port                      = 4000
  ip_protocol                  = "tcp"
  description                  = "Workspaces to LiteLLM"
}

# Outbound: services can reach anywhere
resource "aws_vpc_security_group_egress_rule" "services_all_outbound" {
  security_group_id = aws_security_group.ecs_services.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# Workspace tasks
resource "aws_security_group" "ecs_workspaces" {
  name        = "${local.name_prefix}-ecs-workspaces"
  description = "Security group for ECS workspace tasks"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-workspaces"
  })
}

# Inbound: ALB to code-server
resource "aws_vpc_security_group_ingress_rule" "workspaces_from_alb" {
  security_group_id            = aws_security_group.ecs_workspaces.id
  referenced_security_group_id = module.alb.alb_security_group_id
  from_port                    = 13337
  to_port                      = 13337
  ip_protocol                  = "tcp"
  description                  = "ALB to code-server"
}

# Outbound: workspaces to services SG on LiteLLM port
resource "aws_vpc_security_group_egress_rule" "workspaces_to_litellm" {
  security_group_id            = aws_security_group.ecs_workspaces.id
  referenced_security_group_id = aws_security_group.ecs_services.id
  from_port                    = 4000
  to_port                      = 4000
  ip_protocol                  = "tcp"
  description                  = "To LiteLLM"
}

# Outbound: DNS resolution (UDP 53)
resource "aws_vpc_security_group_egress_rule" "workspaces_dns" {
  security_group_id = aws_security_group.ecs_workspaces.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  description       = "DNS resolution"
}

# Outbound: HTTPS for package installs and external APIs via NAT
resource "aws_vpc_security_group_egress_rule" "workspaces_https" {
  security_group_id = aws_security_group.ecs_workspaces.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS outbound (NAT)"
}
