###############################################################################
# Secrets Module – Outputs
###############################################################################

output "secret_arns" {
  description = "Map of logical secret name to its ARN."
  value = {
    coder_database            = aws_secretsmanager_secret.coder_database.arn
    coder_oidc                = aws_secretsmanager_secret.coder_oidc.arn
    authentik_secret_key      = aws_secretsmanager_secret.authentik_secret_key.arn
    litellm_master_key        = aws_secretsmanager_secret.litellm_master_key.arn
    litellm_anthropic_api_key = aws_secretsmanager_secret.litellm_anthropic_api_key.arn
    provisioner_secret        = aws_secretsmanager_secret.provisioner_secret.arn
    langfuse_api_keys         = aws_secretsmanager_secret.langfuse_api_keys.arn
    langfuse_auth             = aws_secretsmanager_secret.langfuse_auth.arn
    langfuse_database         = aws_secretsmanager_secret.langfuse_database.arn
    langfuse_clickhouse       = aws_secretsmanager_secret.langfuse_clickhouse.arn
  }
}

output "provisioner_secret_arn" {
  description = "ARN of the key-provisioner shared secret."
  value       = aws_secretsmanager_secret.provisioner_secret.arn
}

output "litellm_master_key_secret_arn" {
  description = "ARN of the LiteLLM master key secret."
  value       = aws_secretsmanager_secret.litellm_master_key.arn
}

output "langfuse_api_keys_secret_arn" {
  description = "ARN of the Langfuse API keys secret."
  value       = aws_secretsmanager_secret.langfuse_api_keys.arn
}

output "langfuse_auth_secret_arn" {
  description = "ARN of the Langfuse auth secrets."
  value       = aws_secretsmanager_secret.langfuse_auth.arn
}

output "langfuse_database_secret_arn" {
  description = "ARN of the Langfuse database connection secret."
  value       = aws_secretsmanager_secret.langfuse_database.arn
}

output "langfuse_clickhouse_secret_arn" {
  description = "ARN of the Langfuse ClickHouse password secret."
  value       = aws_secretsmanager_secret.langfuse_clickhouse.arn
}
