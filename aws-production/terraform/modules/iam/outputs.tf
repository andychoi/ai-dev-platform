###############################################################################
# IAM Module – Outputs
###############################################################################

output "task_execution_role_arn" {
  description = "ARN of the shared ECS task execution role."
  value       = aws_iam_role.task_execution.arn
}

output "coder_task_role_arn" {
  description = "ARN of the Coder ECS task role."
  value       = aws_iam_role.coder.arn
}

output "litellm_task_role_arn" {
  description = "ARN of the LiteLLM ECS task role."
  value       = aws_iam_role.litellm.arn
}

output "authentik_task_role_arn" {
  description = "ARN of the Authentik ECS task role."
  value       = aws_iam_role.authentik.arn
}

output "key_provisioner_task_role_arn" {
  description = "ARN of the Key Provisioner ECS task role."
  value       = aws_iam_role.key_provisioner.arn
}

output "langfuse_task_role_arn" {
  description = "ARN of the Langfuse ECS task role."
  value       = aws_iam_role.langfuse.arn
}

output "workspace_task_role_arn" {
  description = "ARN of the Workspace ECS task role."
  value       = aws_iam_role.workspace.arn
}
