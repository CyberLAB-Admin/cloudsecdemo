#############################################################################
# Cloud Security Demo - Storage Module
# 
# This module handles all storage-related resources including:
# - S3 buckets
# - EBS volumes
# - Backup configurations
# - Encryption settings
# - Access policies
# - Lifecycle rules
#############################################################################

# Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_encryption" {
  description = "Enable encryption for storage resources"
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Block public access to S3 buckets"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

# KMS Key for Encryption
resource "aws_kms_key" "storage" {
  count = var.enable_encryption ? 1 : 0

  description             = "KMS key for storage encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-storage-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "storage" {
  count = var.enable_encryption ? 1 : 0

  name          = "alias/${var.project_name}-storage-key"
  target_key_id = aws_kms_key.storage[0].key_id
}

# Main Storage Bucket
resource "aws_s3_bucket" "main" {
  bucket = "${var.project_name}-${var.environment}-${random_string.bucket_suffix.result}"

  force_destroy = true

  tags = {
    Name        = "${var.project_name}-main"
    Environment = var.environment
  }
}

# Bucket Versioning
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_encryption ? aws_kms_key.storage[0].arn : null
      sse_algorithm     = var.enable_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_encryption
  }
}

# Block Public Access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# Backup Bucket
resource "aws_s3_bucket" "backup" {
  bucket = "${var.project_name}-backup-${var.environment}-${random_string.bucket_suffix.result}"

  force_destroy = true

  tags = {
    Name        = "${var.project_name}-backup"
    Environment = var.environment
  }
}

# Backup Bucket Versioning
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Backup Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_encryption ? aws_kms_key.storage[0].arn : null
      sse_algorithm     = var.enable_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_encryption
  }
}

# Backup Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "backup-expiration"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
}

# Replication Role
resource "aws_iam_role" "replication" {
  count = var.enable_versioning ? 1 : 0

  name = "${var.project_name}-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# Replication Policy
resource "aws_iam_role_policy" "replication" {
  count = var.enable_versioning ? 1 : 0

  name = "${var.project_name}-replication-policy"
  role = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.main.arn,
          aws_s3_bucket.backup.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.main.arn}/*",
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.main.arn}/*",
          "${aws_s3_bucket.backup.arn}/*"
        ]
      }
    ]
  })
}

# Random String for Bucket Names
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Outputs
output "bucket_name" {
  description = "Name of the main S3 bucket"
  value       = aws_s3_bucket.main.id
}

output "backup_bucket_name" {
  description = "Name of the backup S3 bucket"
  value       = aws_s3_bucket.backup.id
}

output "bucket_arn" {
  description = "ARN of the main S3 bucket"
  value       = aws_s3_bucket.main.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.storage[0].arn : null
}

output "encryption_enabled" {
  description = "Whether encryption is enabled"
  value       = var.enable_encryption
}

output "public_access_blocked" {
  description = "Whether public access is blocked"
  value       = var.block_public_access
}

output "versioning_enabled" {
  description = "Whether versioning is enabled"
  value       = var.enable_versioning
}
