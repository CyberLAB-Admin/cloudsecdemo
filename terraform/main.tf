#############################################################################
# Cloud Security Demo - Main Terraform Configuration
# 
# This is the main entry point for Terraform configuration.
# It defines:
# - Provider configuration
# - Backend configuration
# - Resource organization
# - Module inclusion
#############################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = var.terraform_state_bucket
    key            = var.terraform_state_key
    region         = var.aws_region
    dynamodb_table = var.terraform_state_dynamodb_table
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = terraform.workspace
      ManagedBy   = "terraform"
    }
  }
}

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Configure EKS authentication
data "aws_eks_cluster" "cluster" {
  name = module.compute.eks_cluster_name

  depends_on = [module.compute]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.compute.eks_cluster_name

  depends_on = [module.compute]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Networking module
module "networking" {
  source = "./modules/networking"

  project_name    = var.project_name
  environment     = terraform.workspace
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  # Conditional security settings based on workspace
  enable_flow_logs      = terraform.workspace == "secure"
  enable_vpc_endpoints  = terraform.workspace == "secure"
  restrict_default_sg   = terraform.workspace == "secure"
}

# Compute module (EKS and EC2)
module "compute" {
  source = "./modules/compute"

  project_name    = var.project_name
  environment     = terraform.workspace
  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnet_ids
  public_subnets  = module.networking.public_subnet_ids

  eks_version     = var.eks_version
  instance_types  = var.instance_types
  node_group_size = var.node_group_size

  # Conditional security settings
  private_endpoint      = terraform.workspace == "secure"
  encryption_config     = terraform.workspace == "secure"
  restrict_worker_nodes = terraform.workspace == "secure"

  depends_on = [module.networking]
}

# Storage module (S3 and EBS)
module "storage" {
  source = "./modules/storage"

  project_name = var.project_name
  environment  = terraform.workspace

  # Conditional security settings
  enable_encryption     = terraform.workspace == "secure"
  block_public_access  = terraform.workspace == "secure"
  enable_versioning    = terraform.workspace == "secure"

  depends_on = [module.networking]
}

# Monitoring module
module "monitoring" {
  source = "./modules/monitoring"

  project_name    = var.project_name
  environment     = terraform.workspace
  vpc_id          = module.networking.vpc_id
  eks_cluster_name = module.compute.eks_cluster_name

  log_retention_days = var.log_retention_days
  alert_email       = var.alert_email

  # Enable all security monitoring in secure workspace
  enable_security_monitoring = terraform.workspace == "secure"
  enable_audit_logs         = terraform.workspace == "secure"

  depends_on = [
    module.networking,
    module.compute,
    module.storage
  ]
}

# Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.networking.vpc_id
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.compute.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "The endpoint of the EKS cluster"
  value       = module.compute.eks_cluster_endpoint
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = module.storage.bucket_name
}

output "cloudwatch_log_group" {
  description = "The CloudWatch log group name"
  value       = module.monitoring.log_group_name
}

output "security_status" {
  description = "Current security status of the infrastructure"
  value = {
    workspace           = terraform.workspace
    vpc_flow_logs      = module.networking.flow_logs_enabled
    public_access      = !module.storage.public_access_blocked
    encryption_enabled = module.storage.encryption_enabled
    private_endpoint   = module.compute.private_endpoint_enabled
  }
}
