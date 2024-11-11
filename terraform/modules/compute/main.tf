#############################################################################
# Cloud Security Demo - Compute Module
# 
# This module handles all compute resources including:
# - EKS cluster and node groups
# - EC2 instances for MongoDB
# - Auto Scaling Groups
# - Launch Templates
# - Security Groups
# - IAM roles and policies
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

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "public_subnets" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "eks_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
}

variable "instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_size" {
  description = "Size configuration for node groups"
  type        = object({
    min     = number
    max     = number
    desired = number
  })
}

variable "private_endpoint" {
  description = "Enable private endpoint for EKS cluster"
  type        = bool
  default     = true
}

variable "encryption_config" {
  description = "Enable encryption configuration for EKS cluster"
  type        = bool
  default     = true
}

variable "restrict_worker_nodes" {
  description = "Restrict worker node access"
  type        = bool
  default     = true
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  ]
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
}

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-eks-cluster"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-eks-cluster-sg"
    Environment = var.environment
  }
}

# EKS Node Security Group
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-eks-nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-eks-nodes-sg"
    Environment = var.environment
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = var.private_subnets
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = var.private_endpoint
    endpoint_public_access  = !var.private_endpoint
  }

  dynamic "encryption_config" {
    for_each = var.encryption_config ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.eks[0].arn
      }
      resources = ["secrets"]
    }
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name        = "${var.project_name}-eks"
    Environment = var.environment
  }
}

# EKS Node Groups
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnets

  scaling_config {
    desired_size = var.node_group_size.desired
    max_size     = var.node_group_size.max
    min_size     = var.node_group_size.min
  }

  instance_types = var.instance_types

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes
  ]

  tags = {
    Name        = "${var.project_name}-node-group"
    Environment = var.environment
  }
}

# Launch Template for EKS Nodes
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.project_name}-eks-nodes"
  image_id      = data.aws_ami.eks_node.id
  instance_type = var.instance_types[0]

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    cluster_name = aws_eks_cluster.main.name
    endpoint     = aws_eks_cluster.main.endpoint
    cluster_ca   = aws_eks_cluster.main.certificate_authority[0].data
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.restrict_worker_nodes ? "required" : "optional"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-eks-node"
      Environment = var.environment
    }
  }
}

# MongoDB Instance Security Group
resource "aws_security_group" "mongodb" {
  name_prefix = "${var.project_name}-mongodb"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-mongodb-sg"
    Environment = var.environment
  }
}

# MongoDB Instance
resource "aws_instance" "mongodb" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"

  subnet_id                   = var.private_subnets[0]
  vpc_security_group_ids      = [aws_security_group.mongodb.id]
  associate_public_ip_address = false

  root_block_device {
    volume_size = 20
    encrypted   = var.encryption_config
  }

  user_data = templatefile("${path.module}/templates/mongodb-setup.sh.tpl", {
    mongodb_version = "5.0"
  })

  tags = {
    Name        = "${var.project_name}-mongodb"
    Environment = var.environment
  }
}

# KMS Key for EKS Encryption
resource "aws_kms_key" "eks" {
  count = var.encryption_config ? 1 : 0

  description             = "KMS key for EKS cluster encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-eks-key"
    Environment = var.environment
  }
}

# Data sources
data "aws_ami" "eks_node" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_version}-v*"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "mongodb_instance_id" {
  description = "Instance ID of MongoDB server"
  value       = aws_instance.mongodb.id
}

output "mongodb_private_ip" {
  description = "Private IP of MongoDB server"
  value       = aws_instance.mongodb.private_ip
}

output "database_security_group_id" {
  description = "Security group ID for MongoDB"
  value       = aws_security_group.mongodb.id
}

output "private_endpoint_enabled" {
  description = "Whether private endpoint is enabled for EKS"
  value       = var.private_endpoint
}
