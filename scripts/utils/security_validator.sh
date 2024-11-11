#!/bin/bash

#############################################################################
# Cloud Security Demo - Security Validator
# 
# This script validates the security state of the infrastructure. It checks:
# - Security group configurations
# - IAM roles and policies
# - S3 bucket settings
# - EKS security configurations
# - Network ACLs
# - Encryption settings
#
# Usage: 
#   source ./scripts/utils/security_validator.sh
#   validate_security_state [secure|insecure]
#############################################################################

# Source required utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/logger.sh"

#############################################################################
# Security Check Functions
#############################################################################

# Check security group configurations
check_security_groups() {
    local state=$1
    log_debug "Checking security group configurations..."
    
    local violations=0
    
    # Get all security groups tagged with our project
    local sgs=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Project,Values=cloudsecdemo" \
        --query 'SecurityGroups[*].[GroupId]' \
        --output text)
        
    for sg in $sgs; do
        # Check for 0.0.0.0/0 in ingress rules
        local open_ingress=$(aws ec2 describe-security-groups \
            --group-ids "$sg" \
            --query 'SecurityGroups[].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' \
            --output text)
            
        if [[ "$state" == "secure" && -n "$open_ingress" ]]; then
            log_warn "Security group $sg has open ingress rules"
            ((violations++))
        elif [[ "$state" == "insecure" && -z "$open_ingress" ]]; then
            log_warn "Security group $sg has no open ingress rules"
            ((violations++))
        fi
    done
    
    return $violations
}

# Check IAM roles and policies
check_iam_configurations() {
    local state=$1
    log_debug "Checking IAM configurations..."
    
    local violations=0
    
    # Get all IAM roles tagged with our project
    local roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `cloudsecdemo`)].[RoleName]' \
        --output text)
        
    for role in $roles; do
        # Check for overly permissive policies
        local policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text)
        
        for policy in $policies; do
            local policy_doc=$(aws iam get-role-policy --role-name "$role" --policy-name "$policy" --query 'PolicyDocument' --output text)
            
            if echo "$policy_doc" | grep -q '"Action": "\*"'; then
                if [[ "$state" == "secure" ]]; then
                    log_warn "Role $role has wildcard permissions"
                    ((violations++))
                fi
            elif [[ "$state" == "insecure" ]]; then
                log_warn "Role $role has restricted permissions"
                ((violations++))
            fi
        done
    done
    
    return $violations
}

# Check S3 bucket configurations
check_s3_configurations() {
    local state=$1
    log_debug "Checking S3 bucket configurations..."
    
    local violations=0
    
    # Get all S3 buckets with our project prefix
    local buckets=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `cloudsecdemo`)].Name' --output text)
    
    for bucket in $buckets; do
        # Check public access block
        local public_access=$(aws s3api get-public-access-block \
            --bucket "$bucket" \
            --query 'PublicAccessBlockConfiguration' 2>/dev/null)
            
        if [[ "$state" == "secure" ]]; then
            if [[ -z "$public_access" ]] || echo "$public_access" | grep -q "false"; then
                log_warn "Bucket $bucket has public access not fully blocked"
                ((violations++))
            fi
        else
            if [[ -n "$public_access" ]] && echo "$public_access" | grep -q "true"; then
                log_warn "Bucket $bucket has public access blocked"
                ((violations++))
            fi
        fi
        
        # Check encryption
        local encryption=$(aws s3api get-bucket-encryption \
            --bucket "$bucket" 2>/dev/null)
            
        if [[ "$state" == "secure" && -z "$encryption" ]]; then
            log_warn "Bucket $bucket is not encrypted"
            ((violations++))
        elif [[ "$state" == "insecure" && -n "$encryption" ]]; then
            log_warn "Bucket $bucket is encrypted"
            ((violations++))
        fi
    done
    
    return $violations
}

# Check EKS security configurations
check_eks_configurations() {
    local state=$1
    log_debug "Checking EKS security configurations..."
    
    local violations=0
    
    # Get cluster info
    local cluster_name=$(aws eks list-clusters \
        --query 'clusters[?contains(@,`cloudsecdemo`)]' \
        --output text)
        
    if [[ -n "$cluster_name" ]]; then
        # Check encryption configuration
        local encryption=$(aws eks describe-cluster \
            --name "$cluster_name" \
            --query 'cluster.encryptionConfig' \
            --output text)
            
        if [[ "$state" == "secure" && -z "$encryption" ]]; then
            log_warn "EKS cluster $cluster_name has no encryption config"
            ((violations++))
        elif [[ "$state" == "insecure" && -n "$encryption" ]]; then
            log_warn "EKS cluster $cluster_name has encryption enabled"
            ((violations++))
        fi
        
        # Check logging configuration
        local logging=$(aws eks describe-cluster \
            --name "$cluster_name" \
            --query 'cluster.logging.clusterLogging[?enabled==`true`]' \
            --output text)
            
        if [[ "$state" == "secure" && -z "$logging" ]]; then
            log_warn "EKS cluster $cluster_name has no logging enabled"
            ((violations++))
        elif [[ "$state" == "insecure" && -n "$logging" ]]; then
            log_warn "EKS cluster $cluster_name has logging enabled"
            ((violations++))
        fi
    fi
    
    return $violations
}

#############################################################################
# Main Validation Function
#############################################################################

validate_security_state() {
    local target_state=$1
    log_info "Validating $target_state security state..."
    
    local total_violations=0
    
    # Run all security checks
    check_security_groups "$target_state"
    total_violations=$((total_violations + $?))
    
    check_iam_configurations "$target_state"
    total_violations=$((total_violations + $?))
    
    check_s3_configurations "$target_state"
    total_violations=$((total_violations + $?))
    
    check_eks_configurations "$target_state"
    total_violations=$((total_violations + $?))
    
    if [[ $total_violations -gt 0 ]]; then
        log_error "Security validation failed with $total_violations violations"
    else
        log_success "Security validation passed for $target_state state"
    fi
    
    return $total_violations
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        log_error "Usage: $0 [secure|insecure]"
    fi
    validate_security_state "$1"
fi
