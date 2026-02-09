###############################################################################
# ECS EC2 Docker Module – Outputs
###############################################################################

output "capacity_provider_name" {
  description = "Name of the ECS capacity provider for Docker-enabled workspaces."
  value       = aws_ecs_capacity_provider.ec2_docker.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.ecs_docker.arn
}

output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.ecs_docker.name
}

output "security_group_id" {
  description = "Security group ID for EC2 Docker instances."
  value       = aws_security_group.ec2_docker.id
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to EC2 instances."
  value       = aws_iam_role.ecs_instance.arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.ecs_docker.id
}
