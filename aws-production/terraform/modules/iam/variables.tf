###############################################################################
# IAM Module – Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix applied to all resource names for namespacing."
  type        = string
}

# ── ECS References ───────────────────────────────────────────────────────────

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster (used to scope ECS task provisioning permissions)."
  type        = string
}

variable "efs_file_system_arn" {
  description = "ARN of the EFS file system (used for Coder workspace access point creation)."
  type        = string
}

# ── Resource References ─────────────────────────────────────────────────────

variable "secrets_arns" {
  description = <<-EOT
    Map of logical secret name to its ARN. Expected keys:
      coder_database, coder_oidc, authentik_secret_key,
      litellm_master_key, litellm_anthropic_api_key
  EOT
  type        = map(string)
  default     = {}
}

variable "s3_bucket_arns" {
  description = <<-EOT
    Map of logical bucket name to its ARN. Expected keys:
      terraform_state, artifacts
  EOT
  type        = map(string)
  default     = {}
}

# ── Region ──────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region used for constructing resource ARNs (e.g. Bedrock models, CloudWatch Logs)."
  type        = string
  default     = "us-west-2"
}

# ── Tags ────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
