# Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}

variable "enable_security_monitoring" {
  description = "Enable enhanced security monitoring"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Enable audit logging"
  type        = bool
  default     = true
}

# KMS key for log encryption
resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs encryption"
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

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/${var.project_name}/${var.environment}/application"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name        = "${var.project_name}-application-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "audit" {
  count             = var.enable_audit_logs ? 1 : 0
  name              = "/aws/${var.project_name}/${var.environment}/audit"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name        = "${var.project_name}-audit-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-security-monitor"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name        = "${var.project_name}-lambda-logs"
    Environment = var.environment
  }
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-${var.environment}-alerts"
  kms_master_key_id = aws_kms_key.logs.id
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda function for security monitoring
resource "aws_lambda_function" "security_monitor" {
  filename         = "${path.module}/lambda/security_monitor.zip"
  function_name    = "${var.project_name}-security-monitor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs16.x"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      PROJECT_NAME    = var.project_name
      ENVIRONMENT     = var.environment
      SNS_TOPIC_ARN   = aws_sns_topic.alerts.arn
      LOG_GROUP_NAME  = aws_cloudwatch_log_group.lambda.name
    }
  }

  tags = {
    Name        = "${var.project_name}-security-monitor"
    Environment = var.environment
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "config:GetResourceConfigHistory",
          "config:GetComplianceDetailsByConfigRule",
          "config:GetComplianceDetailsByResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# CloudWatch event rule to trigger Lambda
resource "aws_cloudwatch_event_rule" "security_check" {
  name                = "${var.project_name}-security-check"
  description         = "Trigger security monitoring Lambda function"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name        = "${var.project_name}-security-check"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "security_check" {
  rule      = aws_cloudwatch_event_rule.security_check.name
  target_id = "SecurityCheck"
  arn       = aws_lambda_function.security_monitor.arn
}

resource "aws_lambda_permission" "cloudwatch" {
  statement_id  = "AllowCloudWatchInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_check.arn
}

# CloudWatch metrics and alarms
resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  count               = var.enable_security_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-security-group-changes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SecurityGroupEventCount"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors security group changes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name          = "${var.project_name}-root-account-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountUsage"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors root account usage"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }
}

# AWS Config rules
resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  count       = var.enable_security_monitoring ? 1 : 0
  name        = "${var.project_name}-s3-public-read-prohibited"
  description = "Checks that your S3 buckets do not allow public read access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  count       = var.enable_security_monitoring ? 1 : 0
  name        = "${var.project_name}-encrypted-volumes"
  description = "Checks that EBS volumes are encrypted"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "incoming_ssh_disabled" {
  count       = var.enable_security_monitoring ? 1 : 0
  name        = "${var.project_name}-incoming-ssh-disabled"
  description = "Checks that security groups do not allow incoming SSH from 0.0.0.0/0"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# AWS Config recorder
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
    include_global_resource_types = true
  }
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_configuration_recorder.main]
}

# IAM role for Config
resource "aws_iam_role" "config_role" {
  name = "${var.project_name}-config-role"

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

# CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "security" {
  dashboard_name = "${var.project_name}-security"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["CloudTrailMetrics", "SecurityGroupEventCount", "Environment", var.environment],
            [".", "RootAccountUsage", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Security Events"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.security_monitor.function_name],
            [".", "Duration", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Security Monitor Function"
        }
      }
    ]
  })
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Outputs
output "log_group_name" {
  description = "Name of the main CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "lambda_function_name" {
  description = "Name of the security monitoring Lambda function"
  value       = aws_lambda_function.security_monitor.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "config_recorder_id" {
  description = "ID of the AWS Config recorder"
  value       = aws_config_configuration_recorder.main.id
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.security.dashboard_name
}

output "monitoring_status" {
  description = "Status of monitoring components"
  value = {
    security_monitoring_enabled = var.enable_security_monitoring
    audit_logs_enabled         = var.enable_audit_logs
    log_retention_days         = var.log_retention_days
    alerts_configured          = true
  }
}