###############################################################################
# IAM Module – Main
#
# Creates ECS task roles for Fargate services:
#   - Shared task execution role (ECR pull, Secrets Manager, CloudWatch Logs)
#   - coder-task-role            (Secrets Manager, S3, ECS provisioning, EFS)
#   - litellm-task-role          (Bedrock invoke, Secrets Manager)
#   - authentik-task-role        (Secrets Manager, SES)
#   - workspace-task-role        (CloudWatch Logs only)
#   - aem-workspace-task-role    (CloudWatch Logs + S3 artifacts read)
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# Helper: ECS Task Trust Policy
###############################################################################

data "aws_iam_policy_document" "ecs_task_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

###############################################################################
# 1. Shared ECS Task Execution Role
#
# Used by ALL ECS services for:
#   - Pulling images from ECR
#   - Reading secrets from Secrets Manager (prod/*)
#   - Writing logs to CloudWatch
###############################################################################

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution" {
  # Secrets Manager – read all prod/* secrets for container injection
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/*",
    ]
  }

  # CloudWatch Logs – create and write log streams
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}*",
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}*:*",
    ]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${var.name_prefix}-ecs-task-execution-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

###############################################################################
# 2. Coder Task Role
#
# Permissions:
#   - Secrets Manager (coder secrets)
#   - S3 (terraform state for workspace provisioning)
#   - ECS (RunTask, DescribeTaskDefinition, DescribeServices,
#          RegisterTaskDefinition – for workspace provisioning)
#   - EFS (create access points for workspaces)
###############################################################################

resource "aws_iam_role" "coder" {
  name               = "${var.name_prefix}-coder-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "coder" {
  # Secrets Manager – read Coder-specific secrets
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      lookup(var.secrets_arns, "coder_database", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/coder/*"),
      lookup(var.secrets_arns, "coder_oidc", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/coder/*"),
    ]
  }

  # S3 – read/write to terraform state bucket (workspace provisioning)
  statement {
    sid    = "S3ReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      lookup(var.s3_bucket_arns, "terraform_state", ""),
      "${lookup(var.s3_bucket_arns, "terraform_state", "")}/*",
    ]
  }

  # ECS – manage tasks and task definitions for workspace provisioning
  statement {
    sid    = "ECSWorkspaceProvisioning"
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:DescribeTasks",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeServices",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:ListTasks",
    ]
    resources = [
      var.ecs_cluster_arn,
      "${var.ecs_cluster_arn}/*",
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.name_prefix}-workspace*",
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${var.name_prefix}-cluster/*",
    ]
  }

  # IAM – pass execution role and workspace task roles to ECS tasks
  statement {
    sid    = "IAMPassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      aws_iam_role.task_execution.arn,
      aws_iam_role.workspace.arn,
      aws_iam_role.aem_workspace.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # EFS – create and manage access points for workspace volumes
  statement {
    sid    = "EFSAccessPoints"
    effect = "Allow"
    actions = [
      "elasticfilesystem:CreateAccessPoint",
      "elasticfilesystem:DeleteAccessPoint",
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
    ]
    resources = [
      var.efs_file_system_arn,
      "${var.efs_file_system_arn}/*",
      "arn:${data.aws_partition.current.partition}:elasticfilesystem:${var.aws_region}:${data.aws_caller_identity.current.account_id}:access-point/*",
    ]
  }
}

resource "aws_iam_role_policy" "coder" {
  name   = "${var.name_prefix}-coder-task-role-policy"
  role   = aws_iam_role.coder.id
  policy = data.aws_iam_policy_document.coder.json
}

###############################################################################
# 3. LiteLLM Task Role
#
# Permissions:
#   - Bedrock (invoke models)
#   - Secrets Manager (LiteLLM secrets)
###############################################################################

resource "aws_iam_role" "litellm" {
  name               = "${var.name_prefix}-litellm-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "litellm" {
  # Bedrock – invoke models in the configured region
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/*",
    ]
  }

  # Secrets Manager – read LiteLLM-specific secrets
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      lookup(var.secrets_arns, "litellm_master_key", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/litellm/*"),
      lookup(var.secrets_arns, "litellm_anthropic_api_key", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/litellm/*"),
    ]
  }
}

resource "aws_iam_role_policy" "litellm" {
  name   = "${var.name_prefix}-litellm-task-role-policy"
  role   = aws_iam_role.litellm.id
  policy = data.aws_iam_policy_document.litellm.json
}

###############################################################################
# 4. Authentik Task Role
#
# Permissions:
#   - Secrets Manager (Authentik secrets)
#   - SES (send email)
###############################################################################

resource "aws_iam_role" "authentik" {
  name               = "${var.name_prefix}-authentik-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "authentik" {
  # Secrets Manager – read Authentik-specific secrets
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      lookup(var.secrets_arns, "authentik_secret_key", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/authentik/*"),
    ]
  }

  # SES – send emails for authentication flows
  statement {
    sid    = "SESSendEmail"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "authentik" {
  name   = "${var.name_prefix}-authentik-task-role-policy"
  role   = aws_iam_role.authentik.id
  policy = data.aws_iam_policy_document.authentik.json
}

###############################################################################
# 5. Key Provisioner Task Role
#
# Permissions:
#   - Secrets Manager (provisioner secret + LiteLLM master key)
###############################################################################

resource "aws_iam_role" "key_provisioner" {
  name               = "${var.name_prefix}-key-provisioner-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "key_provisioner" {
  # Secrets Manager – read provisioner and LiteLLM secrets
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      lookup(var.secrets_arns, "provisioner_secret", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/key-provisioner/*"),
      lookup(var.secrets_arns, "litellm_master_key", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/litellm/*"),
    ]
  }
}

resource "aws_iam_role_policy" "key_provisioner" {
  name   = "${var.name_prefix}-key-provisioner-task-role-policy"
  role   = aws_iam_role.key_provisioner.id
  policy = data.aws_iam_policy_document.key_provisioner.json
}

###############################################################################
# 6. Langfuse Task Role
#
# Permissions:
#   - Secrets Manager (Langfuse secrets)
#   - S3 (langfuse-events and langfuse-media buckets)
###############################################################################

resource "aws_iam_role" "langfuse" {
  name               = "${var.name_prefix}-langfuse-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "langfuse" {
  # Secrets Manager – read Langfuse-specific secrets
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      lookup(var.secrets_arns, "langfuse_api_keys", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/langfuse/*"),
      lookup(var.secrets_arns, "langfuse_auth", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/langfuse/*"),
      lookup(var.secrets_arns, "langfuse_database", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/langfuse/*"),
      lookup(var.secrets_arns, "langfuse_clickhouse", "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/langfuse/*"),
    ]
  }

  # S3 – read/write to Langfuse event and media buckets
  statement {
    sid    = "S3ReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      lookup(var.s3_bucket_arns, "langfuse-events", ""),
      "${lookup(var.s3_bucket_arns, "langfuse-events", "")}/*",
      lookup(var.s3_bucket_arns, "langfuse-media", ""),
      "${lookup(var.s3_bucket_arns, "langfuse-media", "")}/*",
    ]
  }
}

resource "aws_iam_role_policy" "langfuse" {
  name   = "${var.name_prefix}-langfuse-task-role-policy"
  role   = aws_iam_role.langfuse.id
  policy = data.aws_iam_policy_document.langfuse.json
}

###############################################################################
# 7. Workspace Task Role
#
# Minimal permissions – workspaces access LiteLLM via network,
# not via IAM. Only CloudWatch Logs for observability.
###############################################################################

resource "aws_iam_role" "workspace" {
  name               = "${var.name_prefix}-workspace-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "workspace" {
  # CloudWatch Logs – write workspace logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}-workspace*",
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}-workspace*:*",
    ]
  }
}

resource "aws_iam_role_policy" "workspace" {
  name   = "${var.name_prefix}-workspace-task-role-policy"
  role   = aws_iam_role.workspace.id
  policy = data.aws_iam_policy_document.workspace.json
}

###############################################################################
# 8. AEM Workspace Task Role
#
# Extended workspace role for AEM workspaces that need S3 access to download
# the proprietary AEM quickstart JAR and license from the artifacts bucket.
# Separate from the base workspace role to maintain least-privilege — only
# AEM workspaces get S3 access.
#
# Permissions:
#   - CloudWatch Logs (same as base workspace)
#   - S3 GetObject on artifacts/aem/* (JAR + license download)
#   - S3 ListBucket with aem/ prefix (enumerate available artifacts)
###############################################################################

resource "aws_iam_role" "aem_workspace" {
  name               = "${var.name_prefix}-aem-workspace-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "aem_workspace" {
  # CloudWatch Logs – write workspace logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}-workspace*",
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}-workspace*:*",
    ]
  }

  # S3 – read AEM artifacts (JAR + license) from the artifacts bucket
  # Scoped to aem/* prefix via resource ARN (s3:prefix condition only works on ListBucket)
  statement {
    sid    = "S3ArtifactsRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${lookup(var.s3_bucket_arns, "artifacts", "")}/aem/*",
    ]
  }

  # S3 – list objects under the aem/ prefix only
  statement {
    sid    = "S3ArtifactsList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      lookup(var.s3_bucket_arns, "artifacts", ""),
    ]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["aem/*"]
    }
  }
}

resource "aws_iam_role_policy" "aem_workspace" {
  name   = "${var.name_prefix}-aem-workspace-task-role-policy"
  role   = aws_iam_role.aem_workspace.id
  policy = data.aws_iam_policy_document.aem_workspace.json
}
