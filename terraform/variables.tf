#############################################################################
# Cloud Security Demo - Terraform Variables
# 
# This file defines all variables used across the Terraform configurations.
# Includes:
# - Project settings
# - AWS configuration
# - Infrastructure settings
# - Security configurations
#############################################################################

# Project Variables
variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "cloudsecdemo"
}

variable "environment" {
  description = "Deployment environment (secure or insecure)"
  type        = string
  validation {
    condition     = contains(["secure", "insecure"], var.environment)
    error_message = "Environment must be either 'secure' or 'insecure'."
  }
}

variable "owner_email" {
  description = "Email address of the project owner"
  type        = string
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "terraform_state_key" {
  description = "S3 key for Terraform state"
  type        = string
  default     = "terraform.tfstate"
}

variable "terraform_state_dynamodb_table" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(object({
    cidr = string
    az   = string
  }))
  default     = [
    {
      cidr = "10.0.1.0/24"
      az   = "a"
    },
    {
      cidr = "10.0.2.0/24"
      az   = "b"
    }
  ]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(object({
    cidr = string
    az   = string
  }))
  default     = [
    {
      cidr = "10.0.3.0/24"
      az   = "a"
    },
    {
      cidr = "10.0.4.0/24"
      az   = "b"
    }
  ]
}

# EKS Configuration
variable "eks_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.27"
}

variable "instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_size" {
  description = "Size configuration for EKS node groups"
  type        = object({
    min     = number
    max     = number
    desired = number
  })
  default     = {
    min     = 1
    max     = 4
    desired = 2
  }
}

# Database Configuration
variable "db_instance_type" {
  description = "Instance type for database server"
  type        = string
  default     = "t3.medium"
}

variable "db_storage_size" {
  description = "Storage size in GB for database"
  type        = number
  default     = 20
}

# Monitoring Configuration
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}

# Security Configuration
variable "allowed_ips" {
  description = "List of allowed IP ranges for secure configuration"
  type        = list(string)
  default     = []
}

variable "enable_waf" {
  description = "Enable WAF for secure configuration"
  type        = bool
  default     = true
}

variable "enable_shield" {
  description = "Enable Shield Advanced for secure configuration"
  type        = bool
  default     = false
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = false
}

# Application Configuration
variable "app_port" {
  description = "Port number for the application"
  type        = number
  default     = 3000
}

variable "app_replicas" {
  description = "Number of application replicas"
  type        = number
  default     = 2
}

# Resource Naming
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "cloudsecdemo"
}

variable "environment_abbreviations" {
  description = "Map of environment abbreviations for resource naming"
  type        = map(string)
  default     = {
    secure   = "sec"
    insecure = "insec"
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Module-specific Variables
variable "networking_config" {
  description = "Additional networking configuration options"
  type        = map(string)
  default     = {}
}

variable "compute_config" {
  description = "Additional compute configuration options"
  type        = map(string)
  default     = {}
}

variable "storage_config" {
  description = "Additional storage configuration options"
  type        = map(string)
  default     = {}
}

variable "monitoring_config" {
  description = "Additional monitoring configuration options"
  type        = map(string)
  default     = {}
}

# Conditional Security Settings
variable "security_controls" {
  description = "Map of security controls that can be enabled/disabled"
  type        = map(bool)
  default     = {
    enable_flow_logs        = true
    enable_vpc_endpoints    = true
    enable_encryption      = true
    block_public_access    = true
    enable_versioning      = true
    enforce_imdsv2         = true
    enable_audit_logs      = true
    restrict_default_sg    = true
    enable_private_link    = true
    enforce_mfa            = true
  }
}

# Rate Limiting and Throttling
variable "rate_limits" {
  description = "Rate limiting configuration for various services"
  type        = map(number)
  default     = {
    api_requests_per_second = 10
    max_connections        = 100
    burst_limit           = 20
  }
}

# Feature Flags
variable "features" {
  description = "Feature flags for enabling/disabling various components"
  type        = map(bool)
  default     = {
    enable_monitoring     = true
    enable_alerting      = true
    enable_dashboard     = true
    enable_auto_scaling  = true
    enable_backups       = true
  }
}
