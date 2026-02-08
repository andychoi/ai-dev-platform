# -----------------------------------------------------------------------------
# Coder WebIDE Production — ECS Service Definitions
# Task definitions and services for all platform components
# -----------------------------------------------------------------------------

# =============================================================================
# CODER SERVER
# =============================================================================

resource "aws_cloudwatch_log_group" "coder" {
  name              = "/ecs/${local.name_prefix}/coder"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_service_discovery_service" "coder" {
  name = "coder"

  dns_config {
    namespace_id = module.ecs.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "coder" {
  family                   = "${local.name_prefix}-coder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 4096
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.coder_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "coder"
      image     = var.coder_image
      essential = true

      portMappings = [
        {
          containerPort = 7080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "CODER_ACCESS_URL", value = "https://coder.${var.domain_name}" },
        { name = "CODER_WILDCARD_ACCESS_URL", value = "*.${var.domain_name}" },
        { name = "CODER_HTTP_ADDRESS", value = "0.0.0.0:7080" },
        { name = "CODER_SECURE_AUTH_COOKIE", value = "true" },
        { name = "CODER_OIDC_ISSUER_URL", value = "https://auth.${var.domain_name}/application/o/coder/" },
        { name = "CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE", value = "false" },
        { name = "CODER_TELEMETRY", value = "false" },
        { name = "CODER_MAX_SESSION_EXPIRY", value = "28800" },
      ]

      secrets = [
        {
          name      = "CODER_PG_CONNECTION_URL"
          valueFrom = module.secrets.coder_database_secret_arn
        },
        {
          name      = "CODER_OIDC_CLIENT_ID"
          valueFrom = "${module.secrets.coder_oidc_secret_arn}:client_id::"
        },
        {
          name      = "CODER_OIDC_CLIENT_SECRET"
          valueFrom = "${module.secrets.coder_oidc_secret_arn}:client_secret::"
        },
      ]

      mountPoints = [
        {
          sourceVolume  = "coder-data"
          containerPath = "/home/coder/.config/coderv2"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.coder.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "coder"
        }
      }
    }
  ])

  volume {
    name = "coder-data"

    efs_volume_configuration {
      file_system_id     = module.efs.file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        iam = "ENABLED"
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "coder" {
  name            = "${local.name_prefix}-coder"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.coder.arn
  desired_count   = 1 # OSS: single instance (multi-replica requires Enterprise license)
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arns["coder"]
    container_name   = "coder"
    container_port   = 7080
  }

  service_registries {
    registry_arn = aws_service_discovery_service.coder.arn
  }

  depends_on = [module.alb]

  tags = var.tags
}

# =============================================================================
# LITELLM
# =============================================================================

resource "aws_cloudwatch_log_group" "litellm" {
  name              = "/ecs/${local.name_prefix}/litellm"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_service_discovery_service" "litellm" {
  name = "litellm"

  dns_config {
    namespace_id = module.ecs.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "litellm" {
  family                   = "${local.name_prefix}-litellm"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 2048
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.litellm_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "litellm"
      image     = "ghcr.io/berriai/litellm:main-latest"
      essential = true

      portMappings = [
        {
          containerPort = 4000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "AWS_REGION_NAME", value = var.aws_region },
        # Langfuse observability — async trace callback
        { name = "LANGFUSE_HOST", value = "http://langfuse-web.${local.name_prefix}.local:3000" },
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = module.secrets.litellm_database_secret_arn
        },
        {
          name      = "LITELLM_MASTER_KEY"
          valueFrom = module.secrets.litellm_master_key_secret_arn
        },
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = module.secrets.anthropic_api_key_secret_arn
        },
        {
          name      = "LANGFUSE_PUBLIC_KEY"
          valueFrom = "${module.secrets.langfuse_api_keys_secret_arn}:public_key::"
        },
        {
          name      = "LANGFUSE_SECRET_KEY"
          valueFrom = "${module.secrets.langfuse_api_keys_secret_arn}:secret_key::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.litellm.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "litellm"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "litellm" {
  name            = "${local.name_prefix}-litellm"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.litellm.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arns["litellm"]
    container_name   = "litellm"
    container_port   = 4000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.litellm.arn
  }

  depends_on = [module.alb]

  tags = var.tags
}

# =============================================================================
# KEY PROVISIONER
# =============================================================================

resource "aws_cloudwatch_log_group" "key_provisioner" {
  name              = "/ecs/${local.name_prefix}/key-provisioner"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_service_discovery_service" "key_provisioner" {
  name = "key-provisioner"

  dns_config {
    namespace_id = module.ecs.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "key_provisioner" {
  family                   = "${local.name_prefix}-key-provisioner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.key_provisioner_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "key-provisioner"
      image     = var.key_provisioner_image
      essential = true

      portMappings = [
        {
          containerPort = 8100
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "LITELLM_URL", value = "http://litellm.coder-production.local:4000" },
        { name = "CODER_URL", value = "https://coder.${var.domain_name}" },
      ]

      secrets = [
        {
          name      = "LITELLM_MASTER_KEY"
          valueFrom = module.secrets.litellm_master_key_secret_arn
        },
        {
          name      = "PROVISIONER_SECRET"
          valueFrom = module.secrets.provisioner_secret_arn
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.key_provisioner.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "key-provisioner"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "key_provisioner" {
  name            = "${local.name_prefix}-key-provisioner"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.key_provisioner.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.key_provisioner.arn
  }

  depends_on = [aws_ecs_service.litellm]

  tags = var.tags
}

# =============================================================================
# CLICKHOUSE (analytics DB for Langfuse)
# =============================================================================

resource "aws_cloudwatch_log_group" "clickhouse" {
  name              = "/ecs/${local.name_prefix}/clickhouse"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_service_discovery_service" "clickhouse" {
  name = "clickhouse"

  dns_config {
    namespace_id = module.ecs.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "clickhouse" {
  family                   = "${local.name_prefix}-clickhouse"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 4096
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.langfuse_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "clickhouse"
      image     = "clickhouse/clickhouse-server:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8123
          protocol      = "tcp"
        },
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "CLICKHOUSE_DB", value = "langfuse" },
        { name = "CLICKHOUSE_USER", value = "langfuse" },
      ]

      secrets = [
        {
          name      = "CLICKHOUSE_PASSWORD"
          valueFrom = module.secrets.langfuse_clickhouse_secret_arn
        },
      ]

      mountPoints = [
        {
          sourceVolume  = "clickhouse-data"
          containerPath = "/var/lib/clickhouse"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.clickhouse.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "clickhouse"
        }
      }
    }
  ])

  volume {
    name = "clickhouse-data"

    efs_volume_configuration {
      file_system_id     = module.efs.file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        iam = "ENABLED"
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "clickhouse" {
  name            = "${local.name_prefix}-clickhouse"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.clickhouse.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.clickhouse.arn
  }

  tags = var.tags
}

# =============================================================================
# LANGFUSE WEB (UI + API)
# =============================================================================

resource "aws_cloudwatch_log_group" "langfuse_web" {
  name              = "/ecs/${local.name_prefix}/langfuse-web"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_service_discovery_service" "langfuse_web" {
  name = "langfuse-web"

  dns_config {
    namespace_id = module.ecs.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "langfuse_web" {
  family                   = "${local.name_prefix}-langfuse-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.langfuse_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "langfuse-web"
      image     = "docker.io/langfuse/langfuse:3"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEXTAUTH_URL", value = "https://langfuse.${var.domain_name}" },
        { name = "CLICKHOUSE_URL", value = "http://clickhouse.${local.name_prefix}.local:8123" },
        { name = "CLICKHOUSE_MIGRATION_URL", value = "clickhouse://clickhouse.${local.name_prefix}.local:9000" },
        { name = "CLICKHOUSE_USER", value = "langfuse" },
        { name = "CLICKHOUSE_CLUSTER_ENABLED", value = "false" },
        { name = "HOSTNAME", value = "0.0.0.0" },
        { name = "REDIS_CONNECTION_STRING", value = "redis://${module.elasticache.endpoint}:6379/1" },
        { name = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET", value = module.s3.bucket_names["langfuse-events"] },
        { name = "LANGFUSE_S3_EVENT_UPLOAD_REGION", value = var.aws_region },
        { name = "LANGFUSE_S3_MEDIA_UPLOAD_BUCKET", value = module.s3.bucket_names["langfuse-media"] },
        { name = "LANGFUSE_S3_MEDIA_UPLOAD_REGION", value = var.aws_region },
        { name = "TELEMETRY_ENABLED", value = "false" },
        { name = "NEXT_TELEMETRY_DISABLED", value = "1" },
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = module.secrets.langfuse_database_secret_arn
        },
        {
          name      = "CLICKHOUSE_PASSWORD"
          valueFrom = module.secrets.langfuse_clickhouse_secret_arn
        },
        {
          name      = "NEXTAUTH_SECRET"
          valueFrom = "${module.secrets.langfuse_auth_secret_arn}:nextauth_secret::"
        },
        {
          name      = "SALT"
          valueFrom = "${module.secrets.langfuse_auth_secret_arn}:salt::"
        },
        {
          name      = "ENCRYPTION_KEY"
          valueFrom = "${module.secrets.langfuse_auth_secret_arn}:encryption_key::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.langfuse_web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "langfuse-web"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "langfuse_web" {
  name            = "${local.name_prefix}-langfuse-web"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.langfuse_web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arns["langfuse"]
    container_name   = "langfuse-web"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.langfuse_web.arn
  }

  depends_on = [module.alb, aws_ecs_service.clickhouse]

  tags = var.tags
}

# =============================================================================
# LANGFUSE WORKER (background job processor)
# =============================================================================

resource "aws_cloudwatch_log_group" "langfuse_worker" {
  name              = "/ecs/${local.name_prefix}/langfuse-worker"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_ecs_task_definition" "langfuse_worker" {
  family                   = "${local.name_prefix}-langfuse-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.langfuse_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "langfuse-worker"
      image     = "docker.io/langfuse/langfuse-worker:3"
      essential = true

      portMappings = [
        {
          containerPort = 3030
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "CLICKHOUSE_URL", value = "http://clickhouse.${local.name_prefix}.local:8123" },
        { name = "CLICKHOUSE_MIGRATION_URL", value = "clickhouse://clickhouse.${local.name_prefix}.local:9000" },
        { name = "CLICKHOUSE_USER", value = "langfuse" },
        { name = "CLICKHOUSE_CLUSTER_ENABLED", value = "false" },
        { name = "REDIS_CONNECTION_STRING", value = "redis://${module.elasticache.endpoint}:6379/1" },
        { name = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET", value = module.s3.bucket_names["langfuse-events"] },
        { name = "LANGFUSE_S3_EVENT_UPLOAD_REGION", value = var.aws_region },
        { name = "LANGFUSE_S3_MEDIA_UPLOAD_BUCKET", value = module.s3.bucket_names["langfuse-media"] },
        { name = "LANGFUSE_S3_MEDIA_UPLOAD_REGION", value = var.aws_region },
        { name = "TELEMETRY_ENABLED", value = "false" },
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = module.secrets.langfuse_database_secret_arn
        },
        {
          name      = "CLICKHOUSE_PASSWORD"
          valueFrom = module.secrets.langfuse_clickhouse_secret_arn
        },
        {
          name      = "ENCRYPTION_KEY"
          valueFrom = "${module.secrets.langfuse_auth_secret_arn}:encryption_key::"
        },
        {
          name      = "SALT"
          valueFrom = "${module.secrets.langfuse_auth_secret_arn}:salt::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.langfuse_worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "langfuse-worker"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "langfuse_worker" {
  name            = "${local.name_prefix}-langfuse-worker"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.langfuse_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  depends_on = [aws_ecs_service.clickhouse]

  tags = var.tags
}

# =============================================================================
# AUTHENTIK
# =============================================================================

resource "aws_cloudwatch_log_group" "authentik" {
  name              = "/ecs/${local.name_prefix}/authentik"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_service_discovery_service" "authentik" {
  name = "authentik"

  dns_config {
    namespace_id = module.ecs.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "authentik" {
  family                   = "${local.name_prefix}-authentik"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 2048
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.authentik_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "authentik"
      image     = "ghcr.io/goauthentik/server:latest"
      essential = true
      command   = ["server"]

      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]

      secrets = [
        {
          name      = "AUTHENTIK_POSTGRESQL__HOST"
          valueFrom = "${module.secrets.authentik_database_secret_arn}:host::"
        },
        {
          name      = "AUTHENTIK_POSTGRESQL__USER"
          valueFrom = "${module.secrets.authentik_database_secret_arn}:username::"
        },
        {
          name      = "AUTHENTIK_POSTGRESQL__PASSWORD"
          valueFrom = "${module.secrets.authentik_database_secret_arn}:password::"
        },
        {
          name      = "AUTHENTIK_POSTGRESQL__NAME"
          valueFrom = "${module.secrets.authentik_database_secret_arn}:database::"
        },
        {
          name      = "AUTHENTIK_SECRET_KEY"
          valueFrom = module.secrets.authentik_secret_key_secret_arn
        },
        {
          name      = "AUTHENTIK_REDIS__HOST"
          valueFrom = module.secrets.authentik_redis_host_secret_arn
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.authentik.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "authentik"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "authentik" {
  name            = "${local.name_prefix}-authentik"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.authentik.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arns["authentik"]
    container_name   = "authentik"
    container_port   = 9000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.authentik.arn
  }

  depends_on = [module.alb]

  tags = var.tags
}

