terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  buckets = {
    terraform-state = "${var.name_prefix}-terraform-state"
    backups         = "${var.name_prefix}-backups"
    artifacts       = "${var.name_prefix}-artifacts"
    langfuse-events = "${var.name_prefix}-langfuse-events"
    langfuse-media  = "${var.name_prefix}-langfuse-media"
  }
}

# ------------------------------------------------------------------------------
# Buckets
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = each.value

  tags = merge(var.tags, {
    Name = each.value
  })
}

# ------------------------------------------------------------------------------
# Versioning (all buckets)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# Server-side encryption – SSE-S3 (all buckets)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ------------------------------------------------------------------------------
# Block all public access (all buckets)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Lifecycle – delete old versions after 90 days (backups bucket only)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.this["backups"].id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
