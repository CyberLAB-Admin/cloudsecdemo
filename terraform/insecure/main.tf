# Additional provider configuration for insecure environment
provider "aws" {
  alias = "insecure"
  
  default_tags {
    tags = {
      SecurityState = "insecure"
      DemoEnvironment = "true"
      WARNING = "Intentionally Insecure Configuration"
    }
  }
}

# Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloudsecdemo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "insecure"
}

# Overly permissive Security Group Rules
resource "aws_security_group_rule" "insecure_db_ingress" {
  type              = "ingress"
  from_port         = 27017
  to_port           = 27017
  protocol          = "tcp"
  security_group_id = module.compute.database_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  
  description = "Allow MongoDB access from anywhere (INSECURE)"
}

resource "aws_security_group_rule" "insecure_eks_ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = module.compute.eks_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  
  description = "Allow all TCP traffic (INSECURE)"
}

# Basic VPC Flow Logs (minimal configuration)
resource "aws_flow_log" "insecure_flow_logs" {
  log_destination_type = "cloud-watch-logs"
  log_destination     = aws_cloudwatch_log_group.basic_logs.arn
  traffic_type        = "REJECT"
  vpc_id              = module.networking.vpc_id

  tags = {
    Name = "basic-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "basic_logs" {
  name              = "/aws/vpc/basic-flow-logs"
  retention_in_days = 7  # Minimal retention
}

# S3 Bucket Policy (public access)
resource "aws_s3_bucket_policy" "insecure_bucket" {
  bucket = module.storage.bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadAccess"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.storage.bucket_arn,
          "${module.storage.bucket_arn}/*"
        ]
      }
    ]
  })
}

# Disable S3 Block Public Access
resource "aws_s3_bucket_public_access_block" "insecure" {
  bucket = module.storage.bucket_name

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Basic IAM Role with overly permissive policies
resource "aws_iam_role" "insecure_role" {
  name = "insecure-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "*"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "insecure_policy" {
  name = "insecure-admin-policy"
  role = aws_iam_role.insecure_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "*"
        Resource = "*"
      }
    ]
  })
}

# EKS Configuration with public endpoint
resource "aws_eks_cluster" "insecure" {
  name     = "${var.project_name}-cluster"
  role_arn = aws_iam_role.insecure_role.arn

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access = true
    public_access_cidrs    = ["0.0.0.0/0"]
    subnet_ids             = module.networking.public_subnet_ids
  }

  # Disabled logging
  enabled_cluster_log_types = []

  tags = {
    Name = "${var.project_name}-eks-cluster"
    Environment = var.environment
  }
}

# Network ACLs with permissive rules
resource "aws_network_acl" "insecure" {
  vpc_id = module.networking.vpc_id
  subnet_ids = concat(
    module.networking.private_subnet_ids,
    module.networking.public_subnet_ids
  )

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
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
    Name = "insecure-nacl"
  }
}

# RDS Instance with minimal security
resource "aws_db_instance" "insecure" {
  identifier           = "${var.project_name}-db"
  engine              = "mongodb"
  instance_class      = "db.t3.medium"
  allocated_storage   = 20
  skip_final_snapshot = true

  # Insecure configurations
  publicly_accessible    = true
  storage_encrypted     = false
  deletion_protection   = false
  copy_tags_to_snapshot = false
  
  vpc_security_group_ids = [module.compute.database_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.insecure.name

  tags = {
    Name = "insecure-db"
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "insecure" {
  name       = "insecure-db-subnet"
  subnet_ids = module.networking.public_subnet_ids

  tags = {
    Name = "insecure-db-subnet"
  }
}

# Minimal CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "basic" {
  alarm_name          = "basic-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = "80"
  alarm_description  = "Basic CPU utilization alarm"
  
  dimensions = {
    AutoScalingGroupName = module.compute.asg_name
  }
}

# Load Balancer with HTTP (not HTTPS)
resource "aws_lb" "insecure" {
  name               = "insecure-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.compute.eks_security_group_id]
  subnets           = module.networking.public_subnet_ids

  enable_deletion_protection = false
  enable_http2             = false

  tags = {
    Name = "insecure-lb"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.insecure.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.insecure.arn
  }
}

resource "aws_lb_target_group" "insecure" {
  name     = "insecure-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.networking.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    timeout             = 5
    path                = "/"
    port                = "traffic-port"
    protocol           = "HTTP"
    matcher            = "200"
    unhealthy_threshold = 2
  }

  tags = {
    Name = "insecure-target-group"
    Environment = var.environment
  }
}

# Outputs
output "eks_cluster_endpoint" {
  description = "Endpoint for the insecure EKS cluster"
  value       = aws_eks_cluster.insecure.endpoint
}

output "load_balancer_dns" {
  description = "DNS name of the insecure load balancer"
  value       = aws_lb.insecure.dns_name
}

output "database_endpoint" {
  description = "Endpoint of the insecure database"
  value       = aws_db_instance.insecure.endpoint
}

output "security_warnings" {
  description = "List of intentional security misconfigurations"
  value = [
    "Public database access enabled",
    "Unencrypted storage configured",
    "Open security groups",
    "Public S3 bucket access",
    "Admin IAM permissions",
    "Public EKS endpoint",
    "HTTP-only load balancer",
    "Minimal monitoring enabled"
  ]
}