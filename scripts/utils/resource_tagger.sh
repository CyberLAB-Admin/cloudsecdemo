#!/bin/bash

#############################################################################
# Cloud Security Demo - Resource Tagging Utility
# 
# This script handles the tagging of all resources created by the project.
# It ensures consistent tagging across:
# - EC2 instances and volumes
# - S3 buckets
# - EKS resources
# - Lambda functions
# - CloudWatch resources
# - IAM roles
#
# Usage: ./resource_tagger.sh --project <name> --environment <env> [--dry-run]
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common utilities
source "${SCRIPT_DIR}/logger.sh"

#############################################################################
# Configuration
#############################################################################

# Default values
PROJECT_NAME=""
ENVIRONMENT=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

# Validate required arguments
if [[ -z "$PROJECT_NAME" || -z "$ENVIRONMENT" ]]; then
    log_error "Usage: $0 --project <name> --environment <env> [--dry-run]"
fi

#############################################################################
# Tagging Functions
#############################################################################

# Tag EC2 resources
tag_ec2_resources() {
    log_info "Tagging EC2 resources..."
    
    # Get all EC2 instances
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    for instance in $instances; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would tag instance: $instance"
        else
            aws ec2 create-tags \
                --resources "$instance" \
                --tags \
                    "Key=Project,Value=${PROJECT_NAME}" \
                    "Key=Environment,Value=${ENVIRONMENT}" \
                    "Key=ManagedBy,Value=terraform"
                    
            # Tag associated volumes
            local volumes=$(aws ec2 describe-volumes \
                --filters "Name=attachment.instance-id,Values=${instance}" \
                --query 'Volumes[].VolumeId' \
                --output text)
                
            for volume in $volumes; do
                aws ec2 create-tags \
                    --resources "$volume" \
                    --tags \
                        "Key=Project,Value=${PROJECT_NAME}" \
                        "Key=Environment,Value=${ENVIRONMENT}" \
                        "Key=ManagedBy,Value=terraform"
            done
        fi
    done
}

# Tag S3 buckets
tag_s3_buckets() {
    log_info "Tagging S3 buckets..."
    
    # Get all project buckets
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, '${PROJECT_NAME}')].Name" \
        --output text)
        
    for bucket in $buckets; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would tag bucket: $bucket"
        else
            aws s3api put-bucket-tagging \
                --bucket "$bucket" \
                --tagging "TagSet=[
                    {Key=Project,Value=${PROJECT_NAME}},
                    {Key=Environment,Value=${ENVIRONMENT}},
                    {Key=ManagedBy,Value=terraform}
                ]"
        fi
    done
}

# Tag EKS resources
tag_eks_resources() {
    log_info "Tagging EKS resources..."
    
    # Get EKS cluster
    local cluster_name="${PROJECT_NAME}-cluster"
    
    if aws eks describe-cluster --name "$cluster_name" &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would tag EKS cluster: $cluster_name"
        else
            aws eks tag-resource \
                --resource-arn "$(aws eks describe-cluster \
                    --name "$cluster_name" \
                    --query 'cluster.arn' \
                    --output text)" \
                --tags \
                    "Project=${PROJECT_NAME}" \
                    "Environment=${ENVIRONMENT}" \
                    "ManagedBy=terraform"
        fi
    fi
}

# Tag Lambda functions
tag_lambda_functions() {
    log_info "Tagging Lambda functions..."
    
    # Get all project Lambda functions
    local functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}')].FunctionName" \
        --output text)
        
    for func in $functions; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would tag Lambda function: $func"
        else
            aws lambda tag-resource \
                --resource "$(aws lambda get-function \
                    --function-name "$func" \
                    --query 'Configuration.FunctionArn' \
                    --output text)" \
                --tags \
                    "Project=${PROJECT_NAME}" \
                    "Environment=${ENVIRONMENT}" \
                    "ManagedBy=terraform"
        fi
    done
}

# Tag CloudWatch resources
tag_cloudwatch_resources() {
    log_info "Tagging CloudWatch resources..."
    
    # Tag log groups
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/${PROJECT_NAME}" \
        --query 'logGroups[].logGroupName' \
        --output text)
        
    for log_group in $log_groups; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would tag log group: $log_group"
        else
            aws logs tag-log-group \
                --log-group-name "$log_group" \
                --tags \
                    "Project=${PROJECT_NAME}" \
                    "Environment=${ENVIRONMENT}" \
                    "ManagedBy=terraform"
        fi
    done
}

# Tag IAM roles
tag_iam_roles() {
    log_info "Tagging IAM roles..."
    
    # Get all project IAM roles
    local roles=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, '${PROJECT_NAME}')].RoleName" \
        --output text)
        
    for role in $roles; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would tag IAM role: $role"
        else
            aws iam tag-role \
                --role-name "$role" \
                --tags \
                    "Key=Project,Value=${PROJECT_NAME}" \
                    "Key=Environment,Value=${ENVIRONMENT}" \
                    "Key=ManagedBy,Value=terraform"
        fi
    done
}

# Verify tags
verify_tags() {
    log_info "Verifying resource tags..."
    local errors=0
    
    # Function to check tags
    check_resource_tags() {
        local resource_type=$1
        local resource_id=$2
        local tags=$3
        
        if ! echo "$tags" | jq -e '.[] | select(.Key == "Project" and .Value == "'"${PROJECT_NAME}"'")' >/dev/null; then
            log_error "Missing Project tag on ${resource_type}: ${resource_id}"
            ((errors++))
        fi
        
        if ! echo "$tags" | jq -e '.[] | select(.Key == "Environment" and .Value == "'"${ENVIRONMENT}"'")' >/dev/null; then
            log_error "Missing Environment tag on ${resource_type}: ${resource_id}"
            ((errors++))
        fi
    }
    
    # Check EC2 instances
    aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Reservations[].Instances[].[InstanceId,Tags]' \
        --output json | jq -c '.[]' | while read -r instance; do
            check_resource_tags "EC2" "$(echo "$instance" | jq -r '.[0]')" "$(echo "$instance" | jq '.[1]')"
    done
    
    # Check S3 buckets
    aws s3api list-buckets --query "Buckets[?starts_with(Name, '${PROJECT_NAME}')].Name" --output text | tr '\t' '\n' | while read -r bucket; do
        if [[ -n "$bucket" ]]; then
            tags=$(aws s3api get-bucket-tagging --bucket "$bucket" --query 'TagSet' --output json 2>/dev/null || echo "[]")
            check_resource_tags "S3" "$bucket" "$tags"
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log_warn "Found $errors tag verification errors"
        return 1
    fi
    
    log_success "All resources tagged correctly"
    return 0
}

#############################################################################
# Main Function
#############################################################################

main() {
    log_info "Starting resource tagging process..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Running in dry-run mode - no changes will be made"
    fi
    
    # Run all tagging functions
    tag_ec2_resources
    tag_s3_buckets
    tag_eks_resources
    tag_lambda_functions
    tag_cloudwatch_resources
    tag_iam_roles
    
    # Verify tags if not in dry-run mode
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_tags
    fi
    
    log_success "Resource tagging completed successfully!"
    
    # Summary
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run complete. Run without --dry-run to apply changes."
    else
        log_info "All resources have been tagged with:"
        log_info "  Project: ${PROJECT_NAME}"
        log_info "  Environment: ${ENVIRONMENT}"
        log_info "  ManagedBy: terraform"
    fi
}

# Execute main function
main "$@"
