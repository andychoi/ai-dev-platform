variable "domain_name" {
  description = "Primary domain name for the certificate"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for DNS validation. Leave empty to skip automatic validation."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
