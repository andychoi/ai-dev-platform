###############################################################################
# EFS Module – Outputs
###############################################################################

output "file_system_id" {
  description = "ID of the EFS file system."
  value       = aws_efs_file_system.main.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system."
  value       = aws_efs_file_system.main.arn
}

output "file_system_dns_name" {
  description = "DNS name of the EFS file system."
  value       = aws_efs_file_system.main.dns_name
}

output "security_group_id" {
  description = "Security group ID for EFS mount targets."
  value       = aws_security_group.efs.id
}
