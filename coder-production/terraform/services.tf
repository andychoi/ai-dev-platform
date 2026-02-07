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
  desired_count   = 2
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

