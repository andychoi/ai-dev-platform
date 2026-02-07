# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecs_cluster_name" {
  description = "ECS Fargate cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS Fargate cluster ARN"
  value       = module.ecs.cluster_arn
}

output "alb_dns_name" {
  description = "Internal ALB DNS name (VPN access)"
  value       = module.alb.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.endpoint
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache.endpoint
}

output "efs_file_system_id" {
  description = "EFS file system ID for workspace persistent storage"
  value       = module.efs.file_system_id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for ALB"
  value       = module.acm.certificate_arn
}
