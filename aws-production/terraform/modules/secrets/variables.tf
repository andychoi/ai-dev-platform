###############################################################################
# Secrets Module – Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix applied to secret names (e.g. 'prod'). Secrets are named <prefix>/service/key."
  type        = string
  default     = "prod"
}

# ── RDS ─────────────────────────────────────────────────────────────────────

variable "rds_endpoint" {
  description = "RDS cluster endpoint (hostname only, no port)."
  type        = string
}

variable "rds_master_password" {
  description = "RDS master password used to construct connection strings."
  type        = string
  sensitive   = true
}

# ── Tags ────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
