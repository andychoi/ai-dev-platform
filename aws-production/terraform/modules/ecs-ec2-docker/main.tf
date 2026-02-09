###############################################################################
# ECS EC2 Docker Module – Main
#
# Adds EC2 capacity to an existing ECS Fargate cluster for workspaces that
# need Docker (rootless DinD sidecar). Scales to zero when idle.
#
# Components:
#   - Launch template with ECS-optimized AMI
#   - Auto Scaling Group (min=0, scale-to-zero)
#   - ECS capacity provider with managed scaling
#   - Security group for EC2 instances
#   - IAM instance profile for ECS agent
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}

# Latest ECS-optimized Amazon Linux 2023 AMI
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# -----------------------------------------------------------------------------
# IAM: EC2 Instance Profile for ECS Agent
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ecs_instance" {
  name = "${var.name_prefix}-ecs-docker-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.name_prefix}-ecs-docker-instance"
  role = aws_iam_role.ecs_instance.name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group: EC2 Docker Instances
# -----------------------------------------------------------------------------

resource "aws_security_group" "ec2_docker" {
  name        = "${var.name_prefix}-ec2-docker"
  description = "EC2 instances running Docker-enabled ECS workspaces"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-docker"
  })
}

# Inbound: ECS service communication (tasks on this instance)
resource "aws_vpc_security_group_ingress_rule" "from_self" {
  security_group_id            = aws_security_group.ec2_docker.id
  referenced_security_group_id = aws_security_group.ec2_docker.id
  ip_protocol                  = "-1"
  description                  = "Self — inter-task communication on same host"
}

# Inbound: Allow traffic from additional security groups (e.g., ALB, services)
resource "aws_vpc_security_group_ingress_rule" "from_allowed" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.ec2_docker.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "-1"
  description                  = "From allowed SG ${count.index}"
}

# Outbound: All (NAT gateway handles internet egress)
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.ec2_docker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# -----------------------------------------------------------------------------
# Launch Template
# -----------------------------------------------------------------------------

resource "aws_launch_template" "ecs_docker" {
  name_prefix   = "${var.name_prefix}-ecs-docker-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  vpc_security_group_ids = [aws_security_group.ec2_docker.id]

  # ECS agent config: join the cluster, enable task-level networking
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    cluster_name = var.ecs_cluster_name
  }))

  # EBS root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 required (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-ecs-docker"
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Auto Scaling Group (scale-to-zero capable)
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "ecs_docker" {
  name_prefix         = "${var.name_prefix}-ecs-docker-"
  vpc_zone_identifier = var.subnet_ids

  min_size         = 0
  max_size         = var.max_instances
  desired_capacity = 0

  # Use latest launch template version
  launch_template {
    id      = aws_launch_template.ecs_docker.id
    version = "$Latest"
  }

  # Let ECS manage instance lifecycle
  protect_from_scale_in = true

  # Health checks
  health_check_type         = "EC2"
  health_check_grace_period = 120

  # Instance refresh for AMI updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-ecs-docker"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# -----------------------------------------------------------------------------
# ECS Capacity Provider
# -----------------------------------------------------------------------------

resource "aws_ecs_capacity_provider" "ec2_docker" {
  name = "${var.name_prefix}-ec2-docker"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_docker.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = var.target_capacity_percent
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = var.max_scaling_step
      instance_warmup_period    = 120
    }
  }

  tags = var.tags
}
