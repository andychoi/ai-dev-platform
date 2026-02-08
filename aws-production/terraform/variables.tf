# -----------------------------------------------------------------------------
# Global Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "coder"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------

variable "coder_image" {
  description = "Docker image for Coder server"
  type        = string
  default     = "ghcr.io/coder/coder:latest"
}

variable "workspace_image" {
  description = "Default workspace image (ECR URI in production)"
  type        = string
  default     = "contractor-workspace:latest"
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "rds_allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 100
}

variable "rds_max_allocated_storage" {
  description = "Maximum auto-scaling storage in GB"
  type        = number
  default     = 500
}

# -----------------------------------------------------------------------------
# ElastiCache
# -----------------------------------------------------------------------------

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r6g.large"
}

# -----------------------------------------------------------------------------
# Domain
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Primary domain for the platform"
  type        = string
  default     = "coder.company.com"
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for DNS validation"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Dual-Path: Direct Workspace Access (ALB OIDC Authentication)
# -----------------------------------------------------------------------------

variable "enable_workspace_direct_access" {
  description = "Enable direct ALB→code-server path (Path 2) with OIDC authentication"
  type        = bool
  default     = true
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for ALB authentication (e.g., Authentik, Okta, Azure AD)"
  type        = string
  default     = ""
}

variable "oidc_alb_client_id" {
  description = "OIDC client ID for ALB direct workspace access authentication"
  type        = string
  default     = ""
}

variable "oidc_alb_client_secret" {
  description = "OIDC client secret for ALB direct workspace access authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oidc_token_endpoint" {
  description = "OIDC token endpoint URL"
  type        = string
  default     = ""
}

variable "oidc_authorization_endpoint" {
  description = "OIDC authorization endpoint URL"
  type        = string
  default     = ""
}

variable "oidc_user_info_endpoint" {
  description = "OIDC user info endpoint URL"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "coder-webide"
    ManagedBy = "terraform"
  }
}
