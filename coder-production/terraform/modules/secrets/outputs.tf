###############################################################################
# Secrets Module – Outputs
###############################################################################

output "secret_arns" {
  description = "Map of logical secret name to its ARN."
  value = {
    coder_database          = aws_secretsmanager_secret.coder_database.arn
    coder_oidc              = aws_secretsmanager_secret.coder_oidc.arn
    authentik_secret_key    = aws_secretsmanager_secret.authentik_secret_key.arn
    litellm_master_key      = aws_secretsmanager_secret.litellm_master_key.arn
    litellm_anthropic_api_key = aws_secretsmanager_secret.litellm_anthropic_api_key.arn
  }
}
