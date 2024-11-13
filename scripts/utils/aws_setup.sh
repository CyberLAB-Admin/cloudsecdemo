#!/bin/bash

#############################################################################
# Cloud Security Demo - AWS Setup Utility
# 
# This script handles AWS credentials and configuration validation/setup.
# It provides functions for:
# - Validating AWS credentials
# - Directing users to required permissions
# - Setting up AWS CLI configuration
# - Validating region settings
# - Checking account limits
#
# Usage:
#   source ./scripts/utils/aws_setup.sh
#   validate_aws_setup
#############################################################################

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/logger.sh"

#############################################################################
# Global Variables and Constants
#############################################################################

# AWS CLI default config
DEFAULT_OUTPUT_FORMAT="json"
DEFAULT_REGION=${AWS_DEFAULT_REGION:-"us-east-1"}

# Minimum required service limits
readonly MIN_EC2_INSTANCES=5
readonly MIN_EBS_VOLUME_GB=100
readonly MIN_S3_BUCKETS=5

#############################################################################
# AWS Credential Validation Functions
#############################################################################

# Validate AWS credentials
validate_aws_credentials() {
    log_debug "Validating AWS credentials..."
    
    # Check if credentials are set
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_debug "Environment credentials not found, checking AWS CLI configuration..."
        
        # Check if AWS CLI is configured
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            log_error "No valid AWS credentials found. Please configure AWS CLI or set environment variables."
        fi
    fi
    
    # Validate credentials by making an API call
    local account_info
    if ! account_info=$(aws sts get-caller-identity 2>&1); then
        log_error "Failed to validate AWS credentials: ${account_info}"
    fi
    
    local account_id=$(echo "${account_info}" | jq -r .Account)
    local arn=$(echo "${account_info}" | jq -r .Arn)
    
    log_info "Using AWS account: ${account_id}"
    log_debug "Using IAM principal: ${arn}"
    
    return 0
}

#############################################################################
# Permission Checking Functions
#############################################################################

# Check for required IAM permissions
check_iam_permissions() {
    log_info "Checking AWS CLI configuration and access..."
    
    # Check if AWS CLI is configured and can make API calls
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "Unable to authenticate with AWS. Please ensure your AWS CLI is configured correctly."
    fi

    log_warn "To ensure proper functioning of this demo, please verify your IAM permissions."
    log_warn "Required permissions are documented in docs/AWS_Permissions.json"
    log_warn "Please apply these permissions to the IAM user/role you're using with the AWS CLI."
    
    # Ask user to confirm
    read -p "Have you applied the required permissions from docs/AWS_Permissions.json? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Please apply the required permissions before proceeding. See docs/AWS_Permissions.json for details."
    fi

    log_success "AWS authentication check passed"
    return 0
}

#############################################################################
# Service Limit Checking Functions
#############################################################################

# Check AWS service limits
check_service_limits() {
    log_debug "Checking AWS service limits..."
    
    # Check EC2 instance limits
    local ec2_limit=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --query 'Quota.Value' --output text 2>/dev/null)
    
    if [[ -n "${ec2_limit}" ]] && [[ $(echo "${ec2_limit} < ${MIN_EC2_INSTANCES}" | bc) -eq 1 ]]; then
        log_warn "EC2 instance limit (${ec2_limit}) is below recommended minimum (${MIN_EC2_INSTANCES})"
    fi
    
    # Check other service limits as needed
    log_success "Service limit check completed"
}

#############################################################################
# AWS Configuration Functions
#############################################################################

# Setup AWS CLI configuration
setup_aws_cli() {
    log_debug "Setting up AWS CLI configuration..."
    
    # Ensure AWS CLI directory exists
    mkdir -p ~/.aws
    
    # Check if config file exists
    if [[ ! -f ~/.aws/config ]]; then
        log_debug "Creating AWS CLI config file..."
        cat > ~/.aws/config <<EOF
[default]
region = ${DEFAULT_REGION}
output = ${DEFAULT_OUTPUT_FORMAT}
EOF
    fi
    
    # Set default region if not already set
    aws configure set default.region "${DEFAULT_REGION}"
    aws configure set default.output "${DEFAULT_OUTPUT_FORMAT}"
    
    log_success "AWS CLI configuration completed"
}

#############################################################################
# Region Validation Functions
#############################################################################

# Validate AWS region
validate_aws_region() {
    log_debug "Validating AWS region..."
    
    local current_region=$(aws configure get region)
    
    # Check if region is set
    if [[ -z "${current_region}" ]]; then
        log_error "AWS region is not set"
    fi
    
    # Verify region exists
    if ! aws ec2 describe-regions --region="${current_region}" --query 'Regions[].RegionName' | grep -q "${current_region}"; then
        log_error "Invalid AWS region: ${current_region}"
    fi
    
    log_success "AWS region validation passed: ${current_region}"
}

#############################################################################
# Main AWS Setup Function
#############################################################################

validate_aws_setup() {
    log_info "Starting AWS setup validation..."
    
    validate_aws_credentials
    setup_aws_cli
    validate_aws_region
    check_iam_permissions
    check_service_limits
    
    log_success "AWS setup validation completed successfully"
    return 0
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_aws_setup
fi