#!/bin/bash

#############################################################################
# Cloud Security Demo - Cleanup Script
# 
# This script handles the cleanup of all resources including:
# - Kubernetes resources
# - Infrastructure (Terraform)
# - Monitoring components
# - Associated resources (S3 buckets, logs, etc.)
#
# Usage: ./destroy.sh [--force] [--keep-logs] [--keep-backups]
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source common utilities
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/aws_setup.sh"

#############################################################################
# Configuration
#############################################################################

# Default options
FORCE_DESTROY=false
KEEP_LOGS=false
KEEP_BACKUPS=false

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DESTROY=true
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            --keep-backups)
                KEEP_BACKUPS=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done
}

#############################################################################
# Cleanup Functions
#############################################################################

# Clean Kubernetes resources
cleanup_kubernetes() {
    log_info "Cleaning up Kubernetes resources..."

    if kubectl cluster-info &>/dev/null; then
        # Remove all resources in our namespace
        kubectl delete namespace cloudsecdemo --timeout=5m || true
    else
        log_warn "Unable to connect to Kubernetes cluster - skipping cleanup"
    fi
}

# Clean up monitoring
cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."

    # Remove Lambda function
    local function_name="${PROJECT_NAME}-security-monitor"
    if aws lambda get-function --function-name "$function_name" &>/dev/null; then
        aws lambda delete-function --function-name "$function_name"
    fi

    # Remove CloudWatch log groups
    if [[ "$KEEP_LOGS" != "true" ]]; then
        aws logs describe-log-groups \
            --log-group-name-prefix "/aws/${PROJECT_NAME}" \
            --query 'logGroups[*].logGroupName' \
            --output text | tr '\t' '\n' | while read -r log_group; do
            aws logs delete-log-group --log-group-name "$log_group"
        done
    fi

    # Remove SNS topics
    aws sns list-topics | jq -r ".Topics[].TopicArn" | while read -r topic_arn; do
        if [[ "$topic_arn" == *"${PROJECT_NAME}"* ]]; then
            aws sns delete-topic --topic-arn "$topic_arn"
        fi
    done

    # Remove CloudWatch dashboard
    aws cloudwatch delete-dashboards \
        --dashboard-names "${PROJECT_NAME}-security" || true
}

# Clean up S3 buckets
cleanup_s3() {
    log_info "Cleaning up S3 buckets..."

    # List buckets with project prefix
    aws s3api list-buckets --query "Buckets[?starts_with(Name, '${PROJECT_NAME}')].Name" \
        --output text | tr '\t' '\n' | while read -r bucket; do
        if [[ -n "$bucket" ]]; then
            if [[ "$KEEP_BACKUPS" == "true" && "$bucket" == *"-backup-"* ]]; then
                log_info "Skipping backup bucket: $bucket"
                continue
            fi

            log_info "Emptying and removing bucket: $bucket"
            aws s3 rm "s3://${bucket}" --recursive
            aws s3api delete-bucket --bucket "$bucket"
        fi
    done
}

# Clean up IAM resources
cleanup_iam() {
    log_info "Cleaning up IAM resources..."

    # Remove roles
    aws iam list-roles --query "Roles[?contains(RoleName, '${PROJECT_NAME}')].RoleName" \
        --output text | tr '\t' '\n' | while read -r role; do
        if [[ -n "$role" ]]; then
            # Detach policies
            aws iam list-attached-role-policies --role-name "$role" \
                --query "AttachedPolicies[*].PolicyArn" --output text | tr '\t' '\n' | \
                while read -r policy_arn; do
                    aws iam detach-role-policy \
                        --role-name "$role" \
                        --policy-arn "$policy_arn"
                done

            # Delete inline policies
            aws iam list-role-policies --role-name "$role" \
                --query "PolicyNames[*]" --output text | tr '\t' '\n' | \
                while read -r policy; do
                    aws iam delete-role-policy \
                        --role-name "$role" \
                        --policy-name "$policy"
                done

            # Delete role
            aws iam delete-role --role-name "$role"
        fi
    done
}

# Destroy infrastructure
destroy_infrastructure() {
    log_info "Destroying infrastructure..."

    cd "${PROJECT_ROOT}/terraform"

    # Initialize Terraform if needed
    terraform init

    # Destroy each workspace
    for workspace in secure insecure; do
        if terraform workspace select "$workspace" &>/dev/null; then
            log_info "Destroying $workspace environment..."
            if [[ "$FORCE_DESTROY" == "true" ]]; then
                terraform destroy -auto-approve
            else
                terraform destroy
            fi
        fi
    done

    cd - > /dev/null
}

#############################################################################
# Main Function
#############################################################################

main() {
    log_info "Starting cleanup process..."

    # Parse command line arguments
    parse_arguments "$@"

    # Confirm destruction
    if [[ "$FORCE_DESTROY" != "true" ]]; then
        log_warn "This will destroy all resources associated with the project."
        read -p "Are you sure you want to continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Cleanup cancelled by user"
        fi
    fi

    # Run cleanup steps
    cleanup_kubernetes
    cleanup_monitoring
    cleanup_s3
    cleanup_iam
    destroy_infrastructure

    log_success "Cleanup completed successfully!"
}

# Execute main function
main "$@"
