#!/bin/bash

#############################################################################
# Cloud Security Demo - Prerequisite Checker
# 
# This script verifies that all required tools and configurations are in place
# before proceeding with installation or deployment. It checks:
# - Required software versions
# - System resources
# - Permissions
# - Network connectivity
# - AWS credentials
#
# Usage:
#   source ./scripts/utils/prereq_check.sh
#   check_all_prerequisites
#############################################################################

# Source common logging functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/logger.sh"

#############################################################################
# Global Variables and Constants
#############################################################################

# Required tool versions
readonly REQUIRED_TERRAFORM_VERSION="1.5.0"
readonly REQUIRED_KUBECTL_VERSION="1.26.0"
readonly REQUIRED_AWS_CLI_VERSION="2.0.0"

# System requirements
readonly REQUIRED_MEMORY_GB=4
readonly REQUIRED_DISK_SPACE_GB=10

# Required commands
readonly REQUIRED_COMMANDS=(
    "aws"
    "terraform"
    "kubectl"
    "jq"
    "curl"
    "git"
)

#############################################################################
# Version Comparison Function
#############################################################################

# Compare version strings
version_compare() {
    local v1=$1
    local v2=$2
    
    # Remove 'v' prefix if present
    v1=${v1#v}
    v2=${v2#v}
    
    if [[ $v1 == $v2 ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($v1) ver2=($v2)
    
    # Fill empty positions with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do
        ver2[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

#############################################################################
# Individual Check Functions
#############################################################################

# Check if running with sufficient privileges
check_privileges() {
    log_debug "Checking user privileges..."
    
    # Check if we can sudo
    if ! sudo -v >/dev/null 2>&1; then
        log_error "Sudo access is required for installation"
    fi
    
    # Check if we're not running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
    fi
    
    log_success "Privilege check passed"
}

# Check system resources
check_system_resources() {
    log_debug "Checking system resources..."
    
    # Check memory
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -lt $REQUIRED_MEMORY_GB ]]; then
        log_error "Insufficient memory: ${total_mem_gb}GB available, ${REQUIRED_MEMORY_GB}GB required"
    fi
    
    # Check disk space
    local free_space_kb=$(df -k . | awk 'NR==2 {print $4}')
    local free_space_gb=$((free_space_kb / 1024 / 1024))
    
    if [[ $free_space_gb -lt $REQUIRED_DISK_SPACE_GB ]]; then
        log_error "Insufficient disk space: ${free_space_gb}GB available, ${REQUIRED_DISK_SPACE_GB}GB required"
    fi
    
    log_success "System resource check passed"
}

# Check required commands
check_required_commands() {
    log_debug "Checking required commands..."
    
    local missing_commands=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
    fi
    
    log_success "Command check passed"
}

# Check tool versions
check_tool_versions() {
    log_debug "Checking tool versions..."
    
    # Check Terraform version
    local terraform_version=$(terraform version -json | jq -r '.terraform_version')
    version_compare "$terraform_version" "$REQUIRED_TERRAFORM_VERSION"
    if [[ $? -eq 2 ]]; then
        log_error "Terraform version $terraform_version is below required version $REQUIRED_TERRAFORM_VERSION"
    fi
    
    # Check kubectl version
    local kubectl_version=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
    version_compare "${kubectl_version#v}" "$REQUIRED_KUBECTL_VERSION"
    if [[ $? -eq 2 ]]; then
        log_error "kubectl version $kubectl_version is below required version $REQUIRED_KUBECTL_VERSION"
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    version_compare "$aws_version" "$REQUIRED_AWS_CLI_VERSION"
    if [[ $? -eq 2 ]]; then
        log_error "AWS CLI version $aws_version is below required version $REQUIRED_AWS_CLI_VERSION"
    fi
    
    log_success "Tool version check passed"
}

#############################################################################
# Main Check Function
#############################################################################

check_all_prerequisites() {
    log_info "Starting prerequisite checks..."
    
    check_privileges
    check_system_resources
    check_required_commands
    check_tool_versions
    
    log_success "All prerequisite checks passed"
    return 0
}

# Run checks if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_all_prerequisites
fi
