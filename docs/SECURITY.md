# Security Guide

This document details the security configurations, best practices, and operational security procedures for the Cloud Security Demo infrastructure.

## Security States Overview

### Secure State Configuration

#### Network Security
- VPC Flow Logs enabled
- Private subnets for workloads
- Network ACLs enforced
- Security groups with minimal access
- VPC endpoints for AWS services

#### Access Controls
- Private EKS endpoint
- IAM least privilege enforced
- MFA required for access
- Role-based access control
- Session monitoring enabled

#### Data Protection
- Encryption at rest enabled
- Encryption in transit enforced
- S3 bucket policies enforced
- Backup encryption enabled
- Data classification enforced

#### Monitoring
- CloudWatch logs enabled
- Audit logging active
- Security events monitored
- Alert thresholds set
- Compliance checking enabled

### Insecure State Configuration

> ⚠️ **WARNING**: These configurations are intentionally insecure for demonstration purposes only. Never use in production.

#### Network Security
- Public access allowed
- Open security groups
- Minimal network restrictions
- Direct internet access
- Basic logging only

#### Access Controls
- Public endpoints
- Overly permissive IAM
- No MFA requirement
- Basic authentication
- Minimal access logging

#### Data Protection
- Unencrypted storage
- Public bucket access
- Basic backup config
- No data classification
- Minimal protection

#### Monitoring
- Basic logging only
- No audit trails
- Minimal monitoring
- No alerting
- No compliance checks

## Security Controls

### Network Security Controls

```bash
# Check VPC Flow Logs
aws ec2 describe-flow-logs \
    --filter Name=resource-id,Values=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=cloudsecdemo" \
    --query 'Vpcs[0].VpcId' --output text)

# Review Security Groups
aws ec2 describe-security-groups \
    --filters "Name=tag:Project,Values=cloudsecdemo" \
    --query 'SecurityGroups[*].[GroupName,IpPermissions]'

# Validate Network ACLs
aws ec2 describe-network-acls \
    --filters "Name=tag:Project,Values=cloudsecdemo"
```

### Access Control Management

```bash
# Review IAM Roles
aws iam list-roles \
    --query 'Roles[?contains(RoleName, `cloudsecdemo`)]'

# Check Role Policies
aws iam list-role-policies \
    --role-name cloudsecdemo-app-role

# Validate EKS Access
aws eks describe-cluster \
    --name cloudsecdemo-cluster \
    --query 'cluster.resourcesVpcConfig'
```

### Data Protection Controls

```bash
# Verify Bucket Encryption
aws s3api get-bucket-encryption \
    --bucket cloudsecdemo-data

# Check Bucket Policies
aws s3api get-bucket-policy \
    --bucket cloudsecdemo-data

# Review KMS Keys
aws kms list-keys \
    --query 'Keys[*].[KeyId]' \
    --output text | while read -r key; do
    aws kms describe-key --key-id "$key" \
        --query 'KeyMetadata.[KeyId,Description]'
done
```

## Security Monitoring

### CloudWatch Monitoring

```bash
# Check Metrics
aws cloudwatch get-metric-statistics \
    --namespace "CloudSecDemo" \
    --metric-name "SecurityViolations" \
    --dimensions Name=Environment,Value=secure \
    --start-time $(date -d '1 hour ago' -I'seconds') \
    --end-time $(date -I'seconds') \
    --period 300 \
    --statistics Sum

# View Log Insights
aws logs start-query \
    --log-group-name "/aws/cloudsecdemo/security" \
    --start-time $(date -d '24 hours ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like "SECURITY_VIOLATION"'
```

### Alert Configuration

```yaml
# Alert Thresholds (config.yaml)
monitoring:
  alerts:
    critical:
      security_violations: 1
      failed_access: 5
      encryption_failures: 1
    warning:
      security_violations: 0
      failed_access: 3
      encryption_failures: 0
  notifications:
    email: security@example.com
    slack_webhook: https://hooks.slack.com/...
```

## Security Procedures

### Incident Response

1. **Detection**
```bash
# Check security events
./scripts/utils/security_check.sh --last-hour

# Export security logs
./scripts/utils/export_logs.sh --start-time "1 hour ago"
```

2. **Containment**
```bash
# Switch to secure state
./scripts/toggle.sh quick secure --force

# Isolate affected resources
./scripts/utils/isolate_resource.sh <resource-id>
```

3. **Investigation**
```bash
# Collect forensics data
./scripts/utils/collect_forensics.sh <incident-id>

# Generate incident report
./scripts/utils/incident_report.sh <incident-id>
```

4. **Recovery**
```bash
# Restore from clean backup
./scripts/utils/restore.sh --last-known-good

# Verify security state
./scripts/status.sh --security-check
```

### Security Auditing

#### Regular Audits
```bash
# Weekly security scan
./scripts/utils/security_scan.sh --full

# Export audit report
./scripts/utils/security_scan.sh --export audit-report.pdf

# Review configurations
./scripts/utils/config_review.sh
```

#### Compliance Checks
```bash
# Run compliance scan
./scripts/utils/compliance_check.sh

# Generate compliance report
./scripts/utils/compliance_report.sh

# Check specific standards
./scripts/utils/compliance_check.sh --standard CIS
```

### Access Management

#### Role Management
```bash
# Review role permissions
./scripts/utils/review_permissions.sh

# Update role policies
./scripts/utils/update_role.sh <role-name> --policy <policy-file>

# Rotate credentials
./scripts/utils/rotate_credentials.sh
```

#### Authentication
```bash
# Enable MFA
./scripts/utils/enable_mfa.sh <user-name>

# Review access logs
./scripts/utils/review_access.sh --last-week

# Audit user permissions
./scripts/utils/audit_users.sh
```

## Security Best Practices

### Infrastructure Security
- Use private subnets for workloads
- Enable encryption for all data
- Implement least privilege access
- Enable comprehensive logging
- Regular security updates

### Application Security
- Secure container images
- Regular dependency updates
- Security scanning in CI/CD
- Secrets management
- Input validation

### Operational Security
- Regular security audits
- Incident response planning
- Access review processes
- Change management
- Security training

## Security Testing

### Vulnerability Testing
```bash
# Run vulnerability scan
./scripts/utils/vuln_scan.sh

# Test security controls
./scripts/utils/test_controls.sh

# Penetration testing
./scripts/utils/pentest.sh --safe-mode
```

### Configuration Testing
```bash
# Validate secure config
./scripts/utils/validate_config.sh --security

# Test security groups
./scripts/utils/test_sg.sh

# Verify encryption
./scripts/utils/verify_encryption.sh
```

## Security Maintenance

### Regular Updates
```bash
# Update security components
./scripts/utils/security_update.sh

# Patch systems
./scripts/utils/patch_systems.sh

# Update policies
./scripts/utils/update_policies.sh
```

### Backup Security
```bash
# Verify backup encryption
./scripts/utils/verify_backups.sh

# Test restore process
./scripts/utils/test_restore.sh

# Secure backup rotation
./scripts/utils/rotate_backups.sh
```

## Additional Resources

### Internal Documentation
- [Incident Response Playbook](INCIDENT_RESPONSE.md)
- [Security Architecture](ARCHITECTURE.md)
- [Compliance Guide](COMPLIANCE.md)

### External References
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [EKS Security Documentation](https://docs.aws.amazon.com/eks/latest/userguide/security.html)
- [Terraform Security Guide](https://www.terraform.io/docs/cloud/architectural-details/security.html)

