# Troubleshooting Guide

This guide covers common issues, debugging procedures, and solutions for the Cloud Security Demo infrastructure.

## Quick Diagnostic Tools

```bash
# Run full diagnostic check
./scripts/utils/diagnose.sh

# Check specific components
./scripts/utils/diagnose.sh --component [terraform|kubernetes|monitoring]

# Export diagnostic logs
./scripts/utils/diagnose.sh --export diagnostic-report.json
```

## Common Issues

### Deployment Issues

#### Infrastructure Deployment Failures

```
Error: Error creating VPC: VpcLimitExceeded
```
**Solution:**
```bash
# Check VPC limits
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-F678F1CE

# Request limit increase
aws service-quotas request-service-quota-increase \
    --service-code ec2 \
    --quota-code L-F678F1CE \
    --desired-value 5
```

#### Terraform State Lock
```
Error: Error acquiring the state lock
```
**Solution:**
```bash
# Check lock info
terraform force-unlock -force <LOCK_ID>

# If persists, check DynamoDB
aws dynamodb get-item \
    --table-name terraform-state-lock \
    --key '{"LockID":{"S":"cloudsecdemo-terraform-state"}}'
```

#### EKS Cluster Creation Failures
```
Error: Unknown status BAD_REQUEST when waiting for EKS Cluster
```
**Solution:**
```bash
# Check IAM roles
aws iam get-role --role-name cloudsecdemo-cluster-role

# Verify subnet configuration
aws ec2 describe-subnets \
    --filters "Name=tag:Project,Values=cloudsecdemo" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]'

# Check CloudWatch logs
aws logs tail /aws/eks/cloudsecdemo-cluster
```

### Kubernetes Issues

#### Pod Startup Failures
```
kubectl get pods shows pods in CrashLoopBackOff
```
**Solution:**
```bash
# Check pod logs
kubectl logs -f <pod-name> -n cloudsecdemo

# Check pod details
kubectl describe pod <pod-name> -n cloudsecdemo

# Verify node resources
kubectl describe node <node-name>
```

#### EKS Connection Issues
```
Unable to connect to the server: dial tcp: lookup <cluster>: no such host
```
**Solution:**
```bash
# Update kubeconfig
aws eks update-kubeconfig \
    --name cloudsecdemo-cluster \
    --region <region>

# Check AWS credentials
aws sts get-caller-identity

# Verify cluster status
aws eks describe-cluster --name cloudsecdemo-cluster
```

### Security State Issues

#### State Toggle Failures
```
Error: Security state transition failed
```
**Solution:**
```bash
# Check current state
./scripts/status.sh --security-check

# Force state reset
./scripts/toggle.sh full secure --force

# Verify resources
./scripts/utils/verify_resources.sh
```

#### Security Group Issues
```
Error modifying security group rules
```
**Solution:**
```bash
# List security groups
aws ec2 describe-security-groups \
    --filters "Name=tag:Project,Values=cloudsecdemo"

# Reset to default rules
./scripts/utils/reset_security_groups.sh

# Verify changes
./scripts/utils/verify_security_groups.sh
```

### Monitoring Issues

#### Lambda Function Failures
```
Error: Lambda function timed out
```
**Solution:**
```bash
# Check Lambda logs
aws logs tail /aws/lambda/cloudsecdemo-security-monitor

# Update memory/timeout
aws lambda update-function-configuration \
    --function-name cloudsecdemo-security-monitor \
    --timeout 300 \
    --memory-size 512

# Test function
aws lambda invoke \
    --function-name cloudsecdemo-security-monitor \
    --payload '{}' response.json
```

#### CloudWatch Alert Issues
```
No alerts being received
```
**Solution:**
```bash
# Verify SNS topic
aws sns list-subscriptions

# Check metric data
aws cloudwatch get-metric-statistics \
    --namespace CloudSecDemo \
    --metric-name SecurityViolations \
    --dimensions Name=Environment,Value=secure \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --period 300 \
    --statistics Sum

# Update alert configuration
./scripts/utils/update_alerts.sh
```

## Debugging Procedures

### Infrastructure Debugging

```bash
# Enable Terraform debugging
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log

# Run Terraform with debug output
terraform plan -debug

# Check AWS API calls
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=CreateVpc
```

### Application Debugging

```bash
# Enable pod debugging
kubectl debug <pod-name> -n cloudsecdemo \
    --image=busybox -- sleep infinity

# Check container logs
kubectl logs -f deployment/cloudsecdemo -n cloudsecdemo

# Shell into container
kubectl exec -it deployment/cloudsecdemo -n cloudsecdemo -- /bin/bash
```

### Network Debugging

```bash
# Test connectivity
kubectl run -it --rm debug \
    --image=nicolaka/netshoot \
    --restart=Never -- bash

# Check DNS resolution
kubectl run -it --rm debug \
    --image=busybox \
    --restart=Never -- nslookup kubernetes.default

# Analyze VPC Flow Logs
./scripts/utils/analyze_flow_logs.sh
```

## Recovery Procedures

### State Recovery

```bash
# Backup current state
./scripts/utils/backup_state.sh

# Restore from backup
./scripts/utils/restore_state.sh <backup-id>

# Force state reset
./scripts/utils/reset_state.sh --force
```

### Resource Recovery

```bash
# Recreate failed resources
./scripts/utils/recover_resources.sh

# Verify resource health
./scripts/utils/verify_resources.sh

# Clean up orphaned resources
./scripts/utils/cleanup_resources.sh
```

## Maintenance Procedures

### Log Management

```bash
# Rotate logs
./scripts/utils/rotate_logs.sh

# Archive old logs
./scripts/utils/archive_logs.sh

# Clean up log space
./scripts/utils/cleanup_logs.sh
```

### Backup Verification

```bash
# Verify backups
./scripts/utils/verify_backups.sh

# Test restore process
./scripts/utils/test_restore.sh

# Clean old backups
./scripts/utils/cleanup_backups.sh
```

## Performance Optimization

### Resource Optimization

```bash
# Analyze resource usage
./scripts/utils/analyze_usage.sh

# Optimize configurations
./scripts/utils/optimize_resources.sh

# Monitor performance
./scripts/utils/monitor_performance.sh
```

### Cost Optimization

```bash
# Review costs
./scripts/utils/cost_analysis.sh

# Optimize spending
./scripts/utils/optimize_costs.sh

# Generate cost report
./scripts/utils/cost_report.sh
```

## Support Information

### Getting Help

1. Check documentation:
   - [Installation Guide](INSTALL.md)
   - [Usage Guide](USAGE.md)
   - [Security Guide](SECURITY.md)

2. Generate support bundle:
```bash
./scripts/utils/collect_support_data.sh
```

3. Contact support:
   - Email: support@example.com
   - GitHub Issues: [Create Issue](https://github.com/yourusername/cloudsecdemo/issues)
   - Slack: #cloudsecdemo-support

### Support Data Collection

```bash
# Collect logs
./scripts/utils/collect_logs.sh

# Generate system report
./scripts/utils/system_report.sh

# Export configurations
./scripts/utils/export_configs.sh
```

## Additional Resources

- [AWS Troubleshooting](https://aws.amazon.com/premiumsupport/knowledge-center/)
- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Terraform Troubleshooting](https://www.terraform.io/docs/extend/guides/debugging.html)

