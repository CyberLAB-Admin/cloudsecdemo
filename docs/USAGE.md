# Usage Guide

This guide covers the day-to-day operations and usage of the Cloud Security Demo infrastructure.

## Basic Operations

### Checking Status

```bash
# Basic status check
./scripts/status.sh

# Detailed status with all components
./scripts/status.sh --verbose

# JSON output for programmatic use
./scripts/status.sh --json

# Check specific components
./scripts/status.sh --components=kubernetes,monitoring
```

### Security State Management

#### Quick Toggle (Configuration Only)
```bash
# Switch to secure state
./scripts/toggle.sh quick secure

# Switch to insecure state
./scripts/toggle.sh quick insecure

# Verify state change
./scripts/status.sh --verbose
```

#### Full Toggle (Complete Rebuild)
```bash
# Switch to secure state with full rebuild
./scripts/toggle.sh full secure

# Switch to insecure state with full rebuild
./scripts/toggle.sh full insecure

# Force toggle without confirmation
./scripts/toggle.sh full secure --force
```

### Monitoring Operations

#### View Security Status
```bash
# Check security monitoring
aws lambda invoke \
    --function-name cloudsecdemo-security-monitor \
    --payload '{}' \
    response.json

# View CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name cloudsecdemo-security

# Check recent alerts
aws sns list-subscriptions-by-topic \
    --topic-arn $(aws sns list-topics --query 'Topics[?contains(TopicArn,`cloudsecdemo`)].[TopicArn]' --output text)
```

#### Configure Alerts
```bash
# Add email subscription
./scripts/utils/monitor_deploy.sh --add-subscription email@example.com

# Add Slack webhook
./scripts/utils/monitor_deploy.sh --add-subscription slack --webhook-url <url>

# Update alert thresholds
vim config/config.yaml  # Edit monitoring.alerts section
./scripts/utils/monitor_deploy.sh --update-config
```

## Common Tasks

### Managing Resources

#### Working with EKS
```bash
# Get cluster credentials
aws eks update-kubeconfig --name cloudsecdemo-cluster

# Scale node group
kubectl scale deployment cloudsecdemo --replicas=3

# View pods
kubectl get pods -n cloudsecdemo

# View logs
kubectl logs -f deployment/cloudsecdemo -n cloudsecdemo

# Execute shell in pod
kubectl exec -it deployment/cloudsecdemo -n cloudsecdemo -- /bin/bash
```

#### Managing Data
```bash
# Access MongoDB
kubectl port-forward svc/mongodb 27017:27017 -n cloudsecdemo
# Then connect using mongo client

# Backup database
./scripts/utils/backup.sh --component database

# List S3 backups
aws s3 ls s3://cloudsecdemo-backup/

# Restore from backup
./scripts/utils/backup.sh --restore <backup-date>
```

### Security Operations

#### Audit Resources
```bash
# Run security audit
./scripts/utils/security_audit.sh

# Export audit report
./scripts/utils/security_audit.sh --export audit-report.json

# Check specific services
./scripts/utils/security_audit.sh --services=s3,iam,eks
```

#### View Security Logs
```bash
# Recent security events
aws logs tail /aws/cloudsecdemo/security --since 1h

# Export security logs
aws logs export /aws/cloudsecdemo/security \
    --start-time $(date -d '24 hours ago' +%s) \
    --end-time $(date +%s) \
    --output-file security-logs.json
```

#### Manage Access
```bash
# List IAM roles
./scripts/utils/iam_manager.sh --list-roles

# Update role permissions
./scripts/utils/iam_manager.sh --update-role <role-name>

# Rotate credentials
./scripts/utils/iam_manager.sh --rotate-credentials
```

### Demonstration Scenarios

#### Security Demo Setup
```bash
# 1. Start in secure state
./scripts/toggle.sh full secure

# 2. Run baseline security check
./scripts/status.sh --security-check > baseline.json

# 3. Switch to insecure state
./scripts/toggle.sh quick insecure

# 4. Run comparison check
./scripts/status.sh --security-check > comparison.json

# 5. Generate difference report
./scripts/utils/compare_states.sh baseline.json comparison.json
```

#### Testing Security Tools
```bash
# 1. Deploy test vulnerabilities
./scripts/deploy.sh insecure --with-vulnerabilities

# 2. Run security tool
# Example with AWS Security Hub:
aws securityhub get-findings \
    --filters '{"ResourceTags":[{"Key":"Project","Value":["cloudsecdemo"]}]}'

# 3. Verify detection
./scripts/utils/verify_detections.sh

# 4. Clean up
./scripts/deploy.sh secure
```

## Maintenance Tasks

### Backup and Restore

#### Create Backups
```bash
# Full backup
./scripts/utils/backup.sh --full

# Backup specific components
./scripts/utils/backup.sh --components=database,config

# Scheduled backups
./scripts/utils/backup.sh --schedule daily
```

#### Restore from Backup
```bash
# List available backups
./scripts/utils/backup.sh --list

# Restore full backup
./scripts/utils/backup.sh --restore <backup-id>

# Restore specific components
./scripts/utils/backup.sh --restore <backup-id> --components=database
```

### Updates and Upgrades

```bash
# Check for updates
./scripts/utils/version_check.sh

# Update infrastructure
./scripts/deploy.sh secure --upgrade

# Update monitoring components
./scripts/utils/monitor_deploy.sh --upgrade

# Update security configurations
./scripts/utils/security_update.sh
```

### Troubleshooting

```bash
# Enable debug logging
export DEBUG=true
./scripts/status.sh --verbose

# Check component health
./scripts/utils/health_check.sh

# Collect diagnostics
./scripts/utils/collect_diagnostics.sh

# Reset to known good state
./scripts/deploy.sh secure --force
```

## Best Practices

### Security
- Regularly run security audits
- Review and rotate credentials
- Monitor security alerts
- Keep configurations up to date
- Document changes and incidents

### Operations
- Use version control for configurations
- Maintain backup schedule
- Test restoration procedures
- Monitor resource usage
- Keep documentation current

### Development
- Test changes in isolation
- Use feature branches
- Follow security guidelines
- Document modifications
- Update test cases

## Additional Resources

- [Security Guide](SECURITY.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [API Documentation](API.md)
- [Architecture Overview](ARCHITECTURE.md)

