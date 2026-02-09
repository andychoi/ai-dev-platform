###############################################################################
# ECS Module – Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix applied to all resource names for namespacing."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the Cloud Map namespace is created."
  type        = string
}

variable "service_discovery_domain" {
  description = "Domain for AWS Cloud Map service discovery."
  type        = string
  default     = "coder.internal"
}

variable "additional_capacity_providers" {
  description = "Additional capacity provider names to register on the cluster (e.g., EC2 Docker provider)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
