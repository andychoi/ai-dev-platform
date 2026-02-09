###############################################################################
# ECS EC2 Docker Module – Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix applied to all resource names for namespacing."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group and networking."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs where EC2 instances will launch."
  type        = list(string)
}

variable "ecs_cluster_name" {
  description = "Name of the existing ECS cluster to attach the capacity provider to."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Docker-enabled workspaces."
  type        = string
  default     = "t3.medium"
}

variable "max_instances" {
  description = "Maximum number of EC2 instances in the Auto Scaling Group."
  type        = number
  default     = 3
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB. Needs space for Docker images."
  type        = number
  default     = 50
}

variable "target_capacity_percent" {
  description = "Target capacity utilization percentage for managed scaling (100 = pack instances fully)."
  type        = number
  default     = 100
}

variable "max_scaling_step" {
  description = "Maximum number of instances to scale at once."
  type        = number
  default     = 2
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to communicate with EC2 Docker instances (e.g., ALB, services)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
