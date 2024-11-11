#!/bin/bash

#############################################################################
# Cloud Security Demo - Quick Toggle Script
# 
# This script performs configuration-only changes between secure and insecure
# states. It modifies:
# - Security group rules
# - IAM policies
# - S3 bucket policies
# - EKS security configurations
# Without rebuilding the infrastructure.
#
# Usage: ./quick-toggle.sh [secure|insecure]
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source utility scripts
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/aws_setup.sh"

#############################################################################
# Configuration Functions
#############################################################################

# Update security group rules
update_security_groups() {
    local target_state=$1
    log_info "Updating security group rules..."
    
    # Get security group IDs
    local db_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Project,Values=cloudsecdemo" "Name=tag:Component,Values=database" \
        --query 'SecurityGroups[0].GroupId' --output text)
        
    local app_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Project,Values=cloudsecdemo" "Name=tag:Component,Values=application" \
        --query 'SecurityGroups[0].GroupId' --output text)

    # Update rules based on state
    if [[ "$target_state" == "secure" ]]; then
        # Secure state: Restrict access
        aws ec2 revoke-security-group-ingress --group-id $db_sg_id \
            --protocol tcp --port 27017 --cidr 0.0.0.0/0

        aws ec2 authorize-security-group-ingress --group-id $db_sg_id \
            --protocol tcp --port 27017 --source-group $app_sg_id
    else
        # Insecure state: Open access
        aws ec2 revoke-security-group-ingress --group-id $db_sg_id \
            --protocol tcp --port 27017 --source-group $app_sg_id

        aws ec2 authorize-security-group-ingress --group-id $db_sg_id \
            --protocol tcp --port 27017 --cidr 0.0.0.0/0
    fi
}

# Update S3 bucket policies
update_s3_policies() {
    local target_state=$1
    log_info "Updating S3 bucket policies..."
    
    local bucket_name=$(aws s3 ls | grep cloudsecdemo | awk '{print $3}')
    
    if [[ "$target_state" == "secure" ]]; then
        # Secure state: Block public access
        aws s3api put-public-access-block --bucket $bucket_name \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
            
        # Enable encryption
        aws s3api put-bucket-encryption --bucket $bucket_name \
            --server-side-encryption-configuration \
            '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    else
        # Insecure state: Allow public access
        aws s3api delete-public-access-block --bucket $bucket_name
        aws s3api delete-bucket-encryption --bucket $bucket_name
    fi
}

# Update IAM policies
update_iam_policies() {
    local target_state=$1
    log_info "Updating IAM policies..."
    
    local role_name="cloudsecdemo-app-role"
    
    if [[ "$target_state" == "secure" ]]; then
        # Secure state: Least privilege
        aws iam put-role-policy --role-name $role_name \
            --policy-name app-policy \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:PutObject"
                    ],
                    "Resource": "arn:aws:s3:::cloudsecdemo-*/*"
                }]
            }'
    else
        # Insecure state: Overly permissive
        aws iam put-role-policy --role-name $role_name \
            --policy-name app-policy \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Action": "*",
                    "Resource": "*"
                }]
            }'
    fi
}

# Update EKS configuration
update_eks_config() {
    local target_state=$1
    log_info "Updating EKS configuration..."
    
    local cluster_name="cloudsecdemo-cluster"
    
    if [[ "$target_state" == "secure" ]]; then
        # Secure state: Enable security features
        aws eks update-cluster-config --name $cluster_name \
            --encryption-config '[{"resources":["secrets"],"provider":{"keyArn":"auto"}}]'
            
        # Update control plane logging
        aws eks update-cluster-config --name $cluster_name \
            --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
    else
        # Insecure state: Disable security features
        aws eks update-cluster-config --name $cluster_name \
            --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":false}]}'
    fi
}

#############################################################################
# Main Function
#############################################################################

main() {
    if [[ $# -ne 1 ]]; then
        log_error "Usage: $0 [secure|insecure]"
    fi

    local target_state=$1

    # Validate state
    case "$target_state" in
        secure|insecure) ;;
        *) log_error "Invalid state: $target_state" ;;
    esac

    log_info "Starting quick toggle to $target_state state..."

    # Update configurations
    update_security_groups "$target_state"
    update_s3_policies "$target_state"
    update_iam_policies "$target_state"
    update_eks_config "$target_state"

    log_success "Quick toggle to $target_state state completed"
}

# Execute main function
main "$@"
