variable "name_prefix" {
  description = "Prefix for all bucket names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
