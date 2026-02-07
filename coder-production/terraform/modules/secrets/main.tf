###############################################################################
# Secrets Module – Main
#
# Creates AWS Secrets Manager entries for all PoC services:
#   - prod/coder/database          (PostgreSQL connection string)
#   - prod/coder/oidc              (OIDC client credentials – placeholder)
#   - prod/authentik/secret-key    (random generated)
#   - prod/litellm/master-key      (random generated)
#   - prod/litellm/anthropic-api-key (placeholder, optional fallback)
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

###############################################################################
# Random Passwords (for generated secrets)
###############################################################################

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = true
}

resource "random_password" "litellm_master_key" {
  length  = 48
  special = false
}

###############################################################################
# 1. prod/coder/database
###############################################################################

resource "aws_secretsmanager_secret" "coder_database" {
  name        = "${var.name_prefix}/coder/database"
  description = "PostgreSQL connection string for Coder."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "coder_database" {
  secret_id     = aws_secretsmanager_secret.coder_database.id
  secret_string = "postgresql://coder:${var.rds_master_password}@${var.rds_endpoint}:5432/coder?sslmode=require"
}

###############################################################################
# 2. prod/coder/oidc
###############################################################################

resource "aws_secretsmanager_secret" "coder_oidc" {
  name        = "${var.name_prefix}/coder/oidc"
  description = "OIDC client credentials for Coder (placeholder – update manually)."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "coder_oidc" {
  secret_id = aws_secretsmanager_secret.coder_oidc.id
  secret_string = jsonencode({
    client_id     = "PLACEHOLDER_CLIENT_ID"
    client_secret = "PLACEHOLDER_CLIENT_SECRET"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

###############################################################################
# 3. prod/authentik/secret-key
###############################################################################

resource "aws_secretsmanager_secret" "authentik_secret_key" {
  name        = "${var.name_prefix}/authentik/secret-key"
  description = "Authentik secret key (auto-generated)."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "authentik_secret_key" {
  secret_id     = aws_secretsmanager_secret.authentik_secret_key.id
  secret_string = random_password.authentik_secret_key.result
}

###############################################################################
# 4. prod/litellm/master-key
###############################################################################

resource "aws_secretsmanager_secret" "litellm_master_key" {
  name        = "${var.name_prefix}/litellm/master-key"
  description = "LiteLLM master API key (auto-generated)."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "litellm_master_key" {
  secret_id     = aws_secretsmanager_secret.litellm_master_key.id
  secret_string = random_password.litellm_master_key.result
}

###############################################################################
# 6. prod/litellm/anthropic-api-key
###############################################################################

resource "aws_secretsmanager_secret" "litellm_anthropic_api_key" {
  name        = "${var.name_prefix}/litellm/anthropic-api-key"
  description = "Anthropic API key for LiteLLM (placeholder – update manually if needed)."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "litellm_anthropic_api_key" {
  secret_id     = aws_secretsmanager_secret.litellm_anthropic_api_key.id
  secret_string = "PLACEHOLDER_EMPTY"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
