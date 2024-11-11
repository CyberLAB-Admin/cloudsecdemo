# Cloud Security Demo Infrastructure

This project provides a complete infrastructure setup to demonstrate cloud security concepts and test security monitoring tools. It deploys a three-tier application with configurable security states, allowing you to switch between secure and insecure configurations for demonstration and testing purposes.

## Features

- **Configurable Security States**: Switch between secure and insecure configurations
- **Complete Infrastructure Stack**:
  - VPC with public and private subnets
  - EKS cluster with managed node groups
  - MongoDB database
  - S3 storage
  - Monitoring and logging
- **Security Controls**:
  - Network security groups and NACLs
  - IAM roles and policies
  - Encryption settings
  - Access controls
  - Audit logging
- **Monitoring and Alerting**:
  - CloudWatch metrics and logs
  - Custom security monitoring
  - Real-time alerts
  - Security state validation

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0.0
- kubectl
- Docker
- jq
- Python 3.x
- Node.js >= 16.x (for monitoring components)

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/CyberLAB-Admin/cloudsecdemo.git
cd cloudsecdemo
```

2. Run the setup script:
```bash
./scripts/setup.sh
```

3. Configure your environment:
```bash
cp config/defaults/config.yaml.example config/config.yaml
cp config/defaults/.env.example .env

# Edit configurations
vim config.yaml
vim .env
```

4. Deploy the infrastructure:
```bash
# Deploy in secure state
./scripts/deploy.sh secure

# Or deploy in insecure state
./scripts/deploy.sh insecure
```

5. Check the status:
```bash
./scripts/status.sh --verbose
```

## Security States

### Secure State
- Private EKS endpoint
- Encrypted storage
- Restricted security groups
- Least privilege IAM roles
- Network segmentation
- Audit logging enabled

### Insecure State
- Public endpoints
- Unencrypted storage
- Open security groups
- Overly permissive IAM roles
- Minimal network restrictions
- Basic logging

## Usage

### Toggle Security State
```bash
# Quick toggle (configuration only)
./scripts/toggle.sh quick secure

# Full rebuild
./scripts/toggle.sh full secure
```

### Monitor Security Status
```bash
# Check current security status
./scripts/status.sh

# Get detailed JSON output
./scripts/status.sh --json --verbose
```

### Cleanup
```bash
# Remove all resources
./scripts/destroy.sh

# Keep logs and backups
./scripts/destroy.sh --keep-logs --keep-backups
```

## Directory Structure
```
cloudsecdemo/
├── scripts/              # Deployment and utility scripts
├── terraform/            # Infrastructure as Code
├── kubernetes/           # Kubernetes configurations
├── monitoring/           # Security monitoring components
├── config/              # Configuration files
└── docs/                # Documentation
```

## Configuration

### Environment Variables
See `.env.example` for required environment variables:
- `AWS_REGION`: AWS region for deployment
- `PROJECT_NAME`: Project name for resource tagging
- `ENVIRONMENT`: Current environment (secure/insecure)
- `ALERT_EMAIL`: Email for security alerts

### Infrastructure Configuration
Edit `config.yaml` to configure:
- VPC and subnet settings
- EKS cluster configuration
- Database settings
- Monitoring preferences
- Security controls

## Monitoring

The project includes comprehensive security monitoring:
- Real-time security state validation
- Configuration drift detection
- Compliance checking
- Automated remediation options
- Alert notifications

Access the monitoring dashboard:
```
https://<aws-region>.console.aws.amazon.com/cloudwatch/home?region=<region>#dashboards:name=cloudsecdemo-security
```

## Development

### Adding New Security Controls
1. Define control in `config.yaml`
2. Implement in Terraform
3. Add to monitoring checks
4. Update toggle scripts

### Testing Changes
```bash
# Test deployment
./scripts/deploy.sh secure --dry-run

# Test security toggle
./scripts/toggle.sh quick secure --dry-run

# Validate configurations
./scripts/utils/validate_config.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Please ensure:
- All scripts are properly documented
- New features include monitoring
- Security states are properly handled
- Tests pass

## Troubleshooting

See `docs/TROUBLESHOOTING.md` for common issues and solutions.

## License

See `LICENSE` file.

## Support

For support:
1. Check the documentation in `docs/`
2. Create an issue on GitHub
3. Contact the maintainers
