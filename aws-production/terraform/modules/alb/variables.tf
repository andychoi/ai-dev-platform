###############################################################################
# ALB Module – Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix applied to all resource names for namespacing."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB and security group are created."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the internal ALB placement."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for the HTTPS listener."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block used to restrict inbound ALB traffic."
  type        = string
}

variable "domain_name" {
  description = "Base domain name for host-header routing (e.g. example.com)."
  type        = string
}

# ── Dual-Path: Direct Workspace Access (OIDC-Authenticated) ─────────────────

variable "enable_workspace_direct_access" {
  description = "Enable direct ALB→code-server path (Path 2) with OIDC authentication."
  type        = bool
  default     = true
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for ALB authentication action (e.g., Authentik, Okta, Azure AD)."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID for ALB authentication action."
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret for ALB authentication action."
  type        = string
  default     = ""
  sensitive   = true
}

variable "oidc_token_endpoint" {
  description = "OIDC token endpoint URL. If empty, derived from issuer_url."
  type        = string
  default     = ""
}

variable "oidc_authorization_endpoint" {
  description = "OIDC authorization endpoint URL. If empty, derived from issuer_url."
  type        = string
  default     = ""
}

variable "oidc_user_info_endpoint" {
  description = "OIDC user info endpoint URL. If empty, derived from issuer_url."
  type        = string
  default     = ""
}

# ── Access Logging ───────────────────────────────────────────────────────────

variable "enable_access_logs" {
  description = "Whether to enable ALB access logging to S3."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs. Required if enable_access_logs is true."
  type        = string
  default     = ""
}

variable "access_logs_prefix" {
  description = "S3 key prefix for ALB access logs."
  type        = string
  default     = "alb-logs"
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
