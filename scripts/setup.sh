#!/bin/bash

#############################################################################
# Cloud Security Demo - Main Setup Script
# 
# This is the main setup script that orchestrates the entire setup process.
# It uses the utility scripts to:
# - Validate prerequisites
# - Configure AWS
# - Set up the project structure
# - Initialize configurations
# - Prepare the environment for deployment
#
# Usage: ./setup.sh [--quiet] [--region=REGION] [--profile=PROFILE]
#############################################################################

# Exit on any error
set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source utility scripts
source "${PROJECT_ROOT}/scripts/utils/logger.sh"
source "${PROJECT_ROOT}/scripts/utils/prereq_check.sh"
source "${PROJECT_ROOT}/scripts/utils/aws_setup.sh"

#############################################################################
# Global Variables and Constants
#############################################################################

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_PROFILE="default"

# Configuration paths
CONFIG_DIR="${PROJECT_ROOT}/config"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

#############################################################################
# Argument Parsing
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quiet)
                enable_quiet_mode
                shift
                ;;
            --region=*)
                AWS_DEFAULT_REGION="${1#*=}"
                shift
                ;;
            --profile=*)
                AWS_PROFILE="${1#*=}"
                shift
                ;;
            --help)
                echo "Usage: $0 [--quiet] [--region=REGION] [--profile=PROFILE]"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done
}

#############################################################################
# Setup Functions
#############################################################################

# Initialize project configuration
init_project_config() {
    log_info "Initializing project configuration..."
    
    # Create config directory if it doesn't exist
    mkdir -p "${CONFIG_DIR}"
    
    # Copy example configs if they don't exist
    if [[ ! -f "${CONFIG_DIR}/config.yaml" ]]; then
        cp "${CONFIG_DIR}/defaults/config.yaml.example" "${CONFIG_DIR}/config.yaml"
        log_warn "Created default config.yaml - please review and update"
    fi
    
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        cp "${CONFIG_DIR}/defaults/.env.example" "${PROJECT_ROOT}/.env"
        log_warn "Created default .env file - please review and update"
    fi
    
    log_success "Project configuration initialized"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."
    
    cd "${TERRAFORM_DIR}"
    
    # Initialize Terraform
    if ! terraform init; then
        log_error "Failed to initialize Terraform"
    fi
    
    # Create workspaces if they don't exist
    for workspace in secure insecure; do
        if ! terraform workspace select "${workspace}" 2>/dev/null; then
            log_debug "Creating ${workspace} workspace..."
            terraform workspace new "${workspace}"
        fi
    done
    
    # Return to default workspace
    terraform workspace select secure
    
    cd "${PROJECT_ROOT}"
    
    log_success "Terraform initialization completed"
}

# Validate final setup
validate_setup() {
    log_info "Validating setup..."
    
    # Check if all required files exist
    local required_files=(
        "${CONFIG_DIR}/config.yaml"
        "${PROJECT_ROOT}/.env"
        "${TERRAFORM_DIR}/main.tf"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            log_error "Missing required file: ${file}"
        fi
    done
    
    # Validate Terraform configuration
    cd "${TERRAFORM_DIR}"
    if ! terraform validate; then
        log_error "Terraform validation failed"
    fi
    cd "${PROJECT_ROOT}"
    
    log_success "Setup validation completed"
}

#############################################################################
# Main Setup Function
#############################################################################

main() {
    log_info "Starting Cloud Security Demo setup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_all_prerequisites
    
    # Validate AWS setup
    validate_aws_setup
    
    # Initialize project
    init_project_config
    
    # Initialize Terraform
    init_terraform
    
    # Validate setup
    validate_setup
    
    log_success "Setup completed successfully!"
    
    # Display next steps
    cat <<EOF

Next Steps:
1. Review and update ${CONFIG_DIR}/config.yaml
2. Review and update ${PROJECT_ROOT}/.env
3. Run the deployment script: ./scripts/deploy.sh

For more information, see the documentation in docs/
EOF
}

# Run main function
main "$@"
