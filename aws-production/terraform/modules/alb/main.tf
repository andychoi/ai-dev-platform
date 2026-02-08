###############################################################################
# ALB Module – Main
#
# Creates an internal Application Load Balancer with:
#   - HTTPS listener (443) using ACM certificate
#   - Host-header routing rules for Coder, Authentik, LiteLLM
#   - Wildcard routing for Coder workspace subdomain apps
#   - IP-type target groups (required for Fargate awsvpc networking)
#   - Security group: inbound 443 from VPC CIDR only
#   - Optional access logging to S3
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Security group for internal ALB – allows HTTPS from VPC only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from VPC CIDR"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound to VPC for target health checks and traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

###############################################################################
# Application Load Balancer (Internal)
###############################################################################

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb"
  })
}

###############################################################################
# Target Groups
###############################################################################

locals {
  target_groups = {
    coder = {
      port        = 7080
      health_path = "/api/v2/buildinfo"
    }
    litellm = {
      port        = 4000
      health_path = "/health/readiness"
    }
    key_provisioner = {
      port        = 8100
      health_path = "/health"
    }
    langfuse = {
      port        = 3000
      health_path = "/api/public/health"
    }
  }
}

resource "aws_lb_target_group" "services" {
  for_each = local.target_groups

  name        = "${var.name_prefix}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value.health_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-${each.key}"
    Service = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# HTTPS Listener (443)
###############################################################################

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }

  tags = var.tags
}

###############################################################################
# Listener Rules – Host-Header Routing
###############################################################################

resource "aws_lb_listener_rule" "coder" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["coder"].arn
  }

  condition {
    host_header {
      values = ["coder.${var.domain_name}"]
    }
  }

  tags = merge(var.tags, { Service = "coder" })
}

# Platform Admin App (extended Key Provisioner) — OIDC-authenticated
# Hiring manager UI for team management, AI policy, usage dashboards
resource "aws_lb_listener_rule" "admin" {
  count = var.enable_workspace_direct_access && var.oidc_issuer_url != "" ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  action {
    type  = "authenticate-oidc"
    order = 1

    authenticate_oidc {
      issuer                 = var.oidc_issuer_url
      client_id              = var.oidc_client_id
      client_secret          = var.oidc_client_secret
      token_endpoint         = var.oidc_token_endpoint
      authorization_endpoint = var.oidc_authorization_endpoint
      user_info_endpoint     = var.oidc_user_info_endpoint
      on_unauthenticated_request = "authenticate"
      scope                  = "openid profile email"
      session_timeout        = 28800
    }
  }

  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.services["key_provisioner"].arn
  }

  condition {
    host_header {
      values = ["admin.${var.domain_name}"]
    }
  }

  tags = merge(var.tags, { Service = "admin" })
}

resource "aws_lb_listener_rule" "langfuse" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["langfuse"].arn
  }

  condition {
    host_header {
      values = ["langfuse.${var.domain_name}"]
    }
  }

  tags = merge(var.tags, { Service = "langfuse" })
}

resource "aws_lb_listener_rule" "litellm" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 400

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["litellm"].arn
  }

  condition {
    host_header {
      values = ["ai.${var.domain_name}"]
    }
  }

  tags = merge(var.tags, { Service = "litellm" })
}

###############################################################################
# Direct Workspace Access — Path 2 (per-workspace ALB → code-server)
#
# Each workspace creates its OWN target group + listener rule via the
# workspace Terraform template (templates/contractor-workspace/main.tf).
# This ensures:
#   1. User A cannot reach User B's workspace (unique hostname routing)
#   2. ALB OIDC authentication validates identity before forwarding
#   3. code-server --auth proxy validates the OIDC identity header
#
# The ALB module only exports the listener ARN and OIDC config — the
# workspace template uses these to create per-workspace resources:
#   - aws_lb_target_group.workspace (port 13337, single workspace IP)
#   - aws_lb_listener_rule.workspace (OIDC auth + host-header match)
#
# DNS: Route 53 wildcard *.ide.{domain} → ALB (one record, all workspaces)
# Hostname format: {owner}--{ws}.ide.{domain}
# ALB listener rule quota: 100 default (request increase for >100 workspaces)
###############################################################################

###############################################################################
# Coder Wildcard (Path 1 — tunnel access for workspace subdomain apps)
###############################################################################

resource "aws_lb_listener_rule" "coder_wildcard" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 500

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["coder"].arn
  }

  condition {
    host_header {
      values = ["*.${var.domain_name}"]
    }
  }

  tags = merge(var.tags, { Service = "coder-wildcard" })
}
