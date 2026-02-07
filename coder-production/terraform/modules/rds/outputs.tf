output "endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.this.port
}

output "master_password" {
  description = "Master password for the RDS instance"
  value       = random_password.master.result
  sensitive   = true
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.this.name
}

output "security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.this.id
}
