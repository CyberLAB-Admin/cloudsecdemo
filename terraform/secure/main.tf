# Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloudsecdemo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "secure"
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "allowed_ips" {
  description = "List of allowed IP CIDR ranges"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "enable_waf" {
  description = "Enable WAF protection"
  type        = bool
  default     = true
}

# Provider configuration for secure environment
provider "aws" {
  alias = "secure"
  
  default_tags {
    tags = {
      SecurityState = "secure"
      ComplianceRequired = "true"
    }
  }
}

# Security Group Rules
resource "aws_security_group_rule" "secure_db_ingress" {
  type              = "ingress"
  from_port         = 27017
  to_port           = 27017
  protocol          = "tcp"
  security_group_id = module.compute.database_security_group_id
  source_security_group_id = module.compute.eks_security_group_id
  
  description = "Allow MongoDB access only from EKS cluster"
}

resource "aws_security_group_rule" "secure_eks_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.compute.eks_security_group_id
  cidr_blocks       = var.allowed_ips
  
  description = "Allow HTTPS access from specified IPs only"
}

# Enhanced VPC Flow Logs
resource "aws_flow_log" "secure_flow_logs" {
  log_destination_type = "cloud-watch-logs"
  log_destination     = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type        = "ALL"
  vpc_id              = module.networking.vpc_id
  
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id}"

  tags = {
    Name = "secure-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/secure-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secure_logs.arn
}

# KMS Keys for Encryption
resource "aws_kms_key" "secure_logs" {
  description             = "KMS key for secure log encryption"
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
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 Bucket Policy
resource "aws_s3_bucket_policy" "secure_bucket" {
  bucket = module.storage.bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedObjectUploads"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:PutObject"
        Resource = "${module.storage.bucket_arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption": "AES256"
          }
        }
      },
      {
        Sid    = "DenyNonTLSTraffic"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          module.storage.bucket_arn,
          "${module.storage.bucket_arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport": "false"
          }
        }
      }
    ]
  })
}

# WAF Configuration
resource "aws_wafv2_web_acl" "secure_waf" {
  count       = var.enable_waf ? 1 : 0
  name        = "secure-waf"
  description = "WAF rules for secure configuration"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled  = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "secure-waf"
    sampled_requests_enabled  = true
  }
}

# GuardDuty Configuration
resource "aws_guardduty_detector" "secure" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }
}

# Config Rules
resource "aws_config_configuration_recorder" "secure" {
  name     = "secure-config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
    include_global_resource_types = true
  }
}

resource "aws_config_configuration_recorder_status" "secure" {
  name       = aws_config_configuration_recorder.secure.name
  is_enabled = true
}

# IAM Configuration
resource "aws_iam_role" "config_role" {
  name = "secure-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Security Hub
resource "aws_securityhub_account" "secure" {
  enable_default_standards = true
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls     = true
}

# EKS Security Group Rules
resource "aws_security_group_rule" "eks_cluster_secure" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.compute.eks_cluster_security_group_id
  cidr_blocks       = var.allowed_ips

  description = "Allow HTTPS access to EKS API from allowed IPs only"
}

# Additional secure configurations for EKS cluster
resource "aws_eks_addon" "secure_addons" {
  for_each = {
    vpc-cni    = "v1.12.0-eksbuild.1"
    kube-proxy = "v1.24.7-eksbuild.1"
    coredns    = "v1.8.7-eksbuild.1"
  }

  cluster_name = module.compute.eks_cluster_name
  addon_name   = each.key
  addon_version = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Network ACLs
resource "aws_network_acl" "secure" {
  vpc_id = module.networking.vpc_id
  subnet_ids = concat(
    module.networking.private_subnet_ids,
    module.networking.public_subnet_ids
  )

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "secure-nacl"
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Outputs
output "security_controls_status" {
  description = "Status of security controls"
  value = {
    waf_enabled              = var.enable_waf
    guardduty_enabled        = aws_guardduty_detector.secure.enable
    config_enabled           = aws_config_configuration_recorder_status.secure.is_enabled
    security_hub_enabled     = true
    flow_logs_enabled        = true
    encryption_enabled       = true
    private_endpoints_enabled = true
  }
}