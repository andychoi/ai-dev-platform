###############################################################################
# EFS Module – Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix applied to all resource names for namespacing."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EFS security group is created."
  type        = string
}

variable "subnet_ids" {
  description = "Private app subnet IDs for EFS mount targets."
  type        = list(string)
}

variable "allowed_security_groups" {
  description = "Security groups allowed to mount EFS (e.g. ECS service and workspace security groups)."
  type        = list(string)
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
