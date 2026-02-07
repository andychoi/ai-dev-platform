###############################################################################
# EFS Module – Main
#
# Creates an encrypted EFS file system with:
#   - KMS encryption at rest
#   - General-purpose performance mode, bursting throughput
#   - Lifecycle policy: transition to IA after 30 days
#   - Mount targets in each private app subnet
#   - Security group allowing NFS (2049) from specified security groups
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
# KMS Key for EFS Encryption
###############################################################################

resource "aws_kms_key" "efs" {
  description             = "KMS key for ${var.name_prefix} EFS encryption at rest"
  deletion_window_in_days = 14
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-efs"
  })
}

resource "aws_kms_alias" "efs" {
  name          = "alias/${var.name_prefix}-efs"
  target_key_id = aws_kms_key.efs.key_id
}

###############################################################################
# EFS File System
###############################################################################

resource "aws_efs_file_system" "main" {
  encrypted        = true
  kms_key_id       = aws_kms_key.efs.arn
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-efs"
  })
}

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "efs" {
  name_prefix = "${var.name_prefix}-efs-"
  description = "Security group for EFS – allows NFS from authorized security groups"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-efs"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_nfs" {
  for_each = toset(var.allowed_security_groups)

  security_group_id            = aws_security_group.efs.id
  description                  = "Allow NFS from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "efs_all" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

###############################################################################
# Mount Targets (one per subnet)
###############################################################################

resource "aws_efs_mount_target" "main" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}
