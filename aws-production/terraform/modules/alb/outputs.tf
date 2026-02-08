###############################################################################
# ALB Module – Outputs
###############################################################################

output "alb_arn" {
  description = "ARN of the internal Application Load Balancer."
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB (for Route 53 alias records)."
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias records)."
  value       = aws_lb.main.zone_id
}

output "alb_security_group_id" {
  description = "Security group ID attached to the ALB."
  value       = aws_security_group.alb.id
}

output "listener_arn" {
  description = "ARN of the HTTPS listener on port 443."
  value       = aws_lb_listener.https.arn
}

output "target_group_arns" {
  description = "Map of service name to target group ARN."
  value = {
    coder      = aws_lb_target_group.services["coder"].arn
    authentik  = aws_lb_target_group.services["authentik"].arn
    litellm    = aws_lb_target_group.services["litellm"].arn
    workspaces = var.enable_workspace_direct_access ? aws_lb_target_group.workspaces[0].arn : null
  }
}

output "workspace_direct_access_enabled" {
  description = "Whether the direct workspace access path (Path 2) is enabled."
  value       = var.enable_workspace_direct_access
}
