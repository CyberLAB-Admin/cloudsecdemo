#!/bin/bash

#############################################################################
# Cloud Security Demo - Status Checker
# 
# This script checks and reports the status of all components including:
# - Infrastructure state
# - Kubernetes resources
# - Monitoring components
# - Security state
#
# Usage: ./status.sh [--json] [--verbose]
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source common utilities
source "${SCRIPT_DIR}/utils/logger.sh"

#############################################################################
# Configuration
#############################################################################

# Output format
OUTPUT_FORMAT="text"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

#############################################################################
# Status Check Functions
#############################################################################

# Check infrastructure status
check_infrastructure() {
    local result
    declare -A result
    
    # Check Terraform state
    cd "${PROJECT_ROOT}/terraform"
    if terraform show &>/dev/null; then
        result["status"]="OK"
        
        if [[ "$VERBOSE" == "true" ]]; then
            result["vpc_id"]=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
            result["eks_cluster"]=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "N/A")
            result["environment"]=$(terraform workspace show)
        fi
    else
        result["status"]="NOT_FOUND"
    fi
    cd - > /dev/null
    
    echo "$(declare -p result)"
}

# Check Kubernetes status
check_kubernetes() {
    local result
    declare -A result
    
    if kubectl cluster-info &>/dev/null; then
        result["status"]="OK"
        
        if [[ "$VERBOSE" == "true" ]]; then
            result["pods"]=$(kubectl get pods -n cloudsecdemo -o json)
            result["services"]=$(kubectl get services -n cloudsecdemo -o json)
            result["deployments"]=$(kubectl get deployments -n cloudsecdemo -o json)
        fi
    else
        result["status"]="NOT_FOUND"
    fi
    
    echo "$(declare -p result)"
}

# Check monitoring status
check_monitoring() {
    local result
    declare -A result
    
    # Check Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-security-monitor" &>/dev/null; then
        result["lambda_status"]="OK"
        
        if [[ "$VERBOSE" == "true" ]]; then
            result["lambda_details"]=$(aws lambda get-function --function-name "${PROJECT_NAME}-security-monitor" --query 'Configuration.[LastModified,State]' --output json)
        fi
    else
        result["lambda_status"]="NOT_FOUND"
    fi
    
    # Check CloudWatch
    if aws cloudwatch list-dashboards --dashboard-name-prefix "${PROJECT_NAME}" &>/dev/null; then
        result["cloudwatch_status"]="OK"
    else
        result["cloudwatch_status"]="NOT_FOUND"
    fi
    
    # Check SNS topics
    if aws sns list-topics | grep -q "${PROJECT_NAME}"; then
        result["sns_status"]="OK"
    else
        result["sns_status"]="NOT_FOUND"
    fi
    
    echo "$(declare -p result)"
}

# Check security status
check_security() {
    local result
    declare -A result
    
    # Get current security state
    if [[ -f "${PROJECT_ROOT}/config/config.yaml" ]]; then
        result["current_state"]=$(grep "environment:" "${PROJECT_ROOT}/config/config.yaml" | awk '{print $2}')
    else
        result["current_state"]="UNKNOWN"
    fi
    
    # Check recent security events
    if aws lambda invoke \
        --function-name "${PROJECT_NAME}-security-monitor" \
        --payload '{"checkOnly": true}' \
        /tmp/security-check.json &>/dev/null; then
        
        result["security_check"]="OK"
        if [[ "$VERBOSE" == "true" ]]; then
            result["security_details"]=$(cat /tmp/security-check.json)
        fi
    else
        result["security_check"]="FAILED"
    fi
    
    echo "$(declare -p result)"
}

#############################################################################
# Output Formatting Functions
#############################################################################

format_text_output() {
    local infra_status="$1"
    local k8s_status="$2"
    local monitoring_status="$3"
    local security_status="$4"
    
    # Extract values from associative arrays
    eval "$infra_status"
    eval "$k8s_status"
    eval "$monitoring_status"
    eval "$security_status"
    
    cat <<EOF
Cloud Security Demo Status
=========================

Infrastructure Status
--------------------
Status: ${result["status"]}
${VERBOSE && result["vpc_id"]:+VPC ID: ${result["vpc_id"]}}
${VERBOSE && result["eks_cluster"]:+EKS Cluster: ${result["eks_cluster"]}}
${VERBOSE && result["environment"]:+Environment: ${result["environment"]}}

Kubernetes Status
---------------
Status: ${result["status"]}
${VERBOSE && result["pods"]:+Pods: $(echo ${result["pods"]} | jq -r '.items | length')}
${VERBOSE && result["services"]:+Services: $(echo ${result["services"]} | jq -r '.items | length')}
${VERBOSE && result["deployments"]:+Deployments: $(echo ${result["deployments"]} | jq -r '.items | length')}

Monitoring Status
---------------
Lambda: ${result["lambda_status"]}
CloudWatch: ${result["cloudwatch_status"]}
SNS: ${result["sns_status"]}

Security Status
-------------
Current State: ${result["current_state"]}
Security Check: ${result["security_check"]}
EOF
}

format_json_output() {
    local infra_status="$1"
    local k8s_status="$2"
    local monitoring_status="$3"
    local security_status="$4"
    
    # Create JSON structure
    jq -n \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson infrastructure "$(echo "$infra_status" | jq -R 'fromjson')" \
        --argjson kubernetes "$(echo "$k8s_status" | jq -R 'fromjson')" \
        --argjson monitoring "$(echo "$monitoring_status" | jq -R 'fromjson')" \
        --argjson security "$(echo "$security_status" | jq -R 'fromjson')" \
        '{
            timestamp: $timestamp,
            infrastructure: $infrastructure,
            kubernetes: $kubernetes,
            monitoring: $monitoring,
            security: $security
        }'
}

#############################################################################
# Main Function
#############################################################################

main() {
    # Collect status from all components
    local infra_status=$(check_infrastructure)
    local k8s_status=$(check_kubernetes)
    local monitoring_status=$(check_monitoring)
    local security_status=$(check_security)
    
    # Format output
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        format_json_output "$infra_status" "$k8s_status" "$monitoring_status" "$security_status"
    else
        format_text_output "$infra_status" "$k8s_status" "$monitoring_status" "$security_status"
    fi
}

# Execute main function
main "$@"
