# Installation Guide

This guide provides detailed installation instructions for the Cloud Security Demo infrastructure.

## System Requirements

### Hardware Requirements
- CPU: 4+ cores recommended
- RAM: 8GB minimum, 16GB recommended
- Storage: 20GB minimum free space

### Software Requirements

#### Required Tools
- AWS CLI v2 or later
- Terraform >= 1.0.0
- kubectl >= 1.24
- Docker >= 20.10
- Python >= 3.8
- Node.js >= 16.x
- jq >= 1.6

#### AWS Account Requirements
- Admin access or appropriate permissions
- Service quota requirements:
  - EC2: 10 instances
  - EKS: 1 cluster
  - S3: 5 buckets
  - VPC: 1 VPC, 4 subnets
  - EBS: 100GB storage

## Installation Steps

### 1. AWS Configuration

```bash
# Configure AWS CLI
aws configure

# Verify configuration
aws sts get-caller-identity

# Check required permissions
./scripts/utils/aws_setup.sh --check-permissions
```

Required AWS permissions are listed in `docs/AWS_PERMISSIONS.md`.

### 2. Tool Installation

#### Ubuntu/Debian
```bash
# Update package list
sudo apt update

# Install system dependencies
sudo apt install -y \
    python3 python3-pip \
    nodejs npm \
    docker.io \
    jq \
    unzip

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

#### MacOS
```bash
# Install Homebrew if needed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install \
    awscli \
    terraform \
    kubectl \
    docker \
    jq \
    node

# Start Docker
open -a Docker
```

#### Windows (PowerShell)
```powershell
# Install Chocolatey if needed
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Install required tools
choco install -y `
    awscli `
    terraform `
    kubernetes-cli `
    docker-desktop `
    jq `
    nodejs

# Start Docker Desktop
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

### 3. Project Setup

```bash
# Clone repository
git clone https://github.com/CyberLAB-Admin/cloudsecdemo
cd cloudsecdemo

# Create configuration files
cp config/defaults/config.yaml.example config/config.yaml
cp config/defaults/.env.example .env

# Edit configurations
# Update with your specific settings:
# - AWS region
# - Project name
# - Alert email
# - Resource sizes
vim config.yaml
vim .env

# Run setup script
./scripts/setup.sh

# Verify installation
./scripts/status.sh --verbose
```

### 4. Initial Deployment

```bash
# Deploy in secure state
./scripts/deploy.sh secure

# Verify deployment
./scripts/status.sh

# Test security monitoring
aws lambda invoke \
    --function-name cloudsecdemo-security-monitor \
    --payload '{}' \
    response.json
```

## Post-Installation Steps

### 1. Configure Monitoring Alerts
```bash
# Verify SNS topic subscription
aws sns list-subscriptions

# Confirm email subscription (check your email)
```

### 2. Configure Kubernetes Access
```bash
# Update kubeconfig
aws eks update-kubeconfig \
    --name cloudsecdemo-cluster \
    --region your-region

# Verify access
kubectl get nodes
```

### 3. Set Up CloudWatch Dashboard
```bash
# Create dashboard
aws cloudwatch get-dashboard \
    --dashboard-name cloudsecdemo-security

# Open in AWS Console
echo "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=cloudsecdemo-security"
```

## Troubleshooting Installation

### Common Issues

1. **AWS Credentials**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify region
aws configure get region
```

2. **Terraform State**
```bash
# Initialize Terraform
cd terraform
terraform init

# Check state
terraform show
```

3. **Docker Issues**
```bash
# Check Docker service
systemctl status docker

# Test Docker
docker run hello-world
```

4. **Kubernetes Connection**
```bash
# Update kubeconfig
aws eks update-kubeconfig \
    --name cloudsecdemo-cluster \
    --region your-region

# Check connection
kubectl cluster-info
```

### Debug Logs
```bash
# Enable debug logging
export DEBUG=true
export VERBOSE_LOGGING=true

# Check CloudWatch logs
aws logs tail /aws/cloudsecdemo
```

## Upgrading

To upgrade an existing installation:

1. Backup current state:
```bash
./scripts/deploy.sh backup
```

2. Update repository:
```bash
git pull origin main
```

3. Run setup script:
```bash
./scripts/setup.sh --upgrade
```

4. Deploy changes:
```bash
./scripts/deploy.sh secure --upgrade
```

## Uninstallation

To remove the installation:

```bash
# Full cleanup
./scripts/destroy.sh

# Keep logs and backups
./scripts/destroy.sh --keep-logs --keep-backups
```

## Next Steps

- Review the [Usage Guide](USAGE.md)
- Configure [Security Settings](SECURITY.md)
- Set up [Monitoring](MONITORING.md)
- Check [Troubleshooting Guide](TROUBLESHOOTING.md)
