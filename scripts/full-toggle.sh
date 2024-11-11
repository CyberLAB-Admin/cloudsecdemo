#!/bin/bash

#############################################################################
# Cloud Security Demo - Full Toggle Script
# 
# This script performs a complete infrastructure rebuild when toggling between
# secure and insecure states. It:
# 1. Destroys existing infrastructure
# 2. Updates configurations
# 3. Rebuilds infrastructure
# 4. Validates new state
#
# Usage: ./full-toggle.sh [secure|insecure] [--skip-backup] [--force]
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source utility scripts
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/aws_setup.sh"
source "${SCRIPT_DIR}/utils/validate_config.sh"

#############################################################################
# Utility Functions
#############################################################################

# Check if resources exist
check_existing_resources() {
    log_debug "Checking for existing resources..."
    
    local resources_exist=false
    
    # Check for EKS cluster
    if aws eks list-clusters --query 'clusters[?contains(@,`cloudsecdemo`)]' --output text | grep -q .; then
        resources_exist=true
    fi
    
    # Check for EC2 instances
    if aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=cloudsecdemo" \
        --query 'Reservations[*].Instances[*].[InstanceId]' \
        --output text | grep -q .; then
        resources_exist=true
    fi
    
    # Check for S3 buckets
    if aws s3 ls | grep -q cloudsecdemo; then
        resources_exist=true
    fi
    
    echo $resources_exist
}

# Save current state
save_state() {
    log_info "Saving current state..."
    local backup_dir="${PROJECT_ROOT}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Export current kubernetes resources
    if kubectl get namespace cloudsecdemo &>/dev/null; then
        kubectl get all -n cloudsecdemo -o yaml > "$backup_dir/kubernetes_resources.yaml"
    fi
    
    # Backup terraform state
    if [[ -f "${PROJECT_ROOT}/terraform/terraform.tfstate" ]]; then
        cp "${PROJECT_ROOT}/terraform/terraform.tfstate" "$backup_dir/"
    fi
    
    # Backup configurations
    cp "${PROJECT_ROOT}/config/config.yaml" "$backup_dir/"
    
    log_success "State backup created in: $backup_dir"
}

#############################################################################
# Infrastructure Management Functions
#############################################################################

# Destroy current infrastructure
destroy_infrastructure() {
    log_info "Destroying current infrastructure..."
    
    # Switch to correct terraform workspace
    cd "${PROJECT_ROOT}/terraform"
    terraform workspace select secure || terraform workspace select insecure
    
    # Run destroy
    terraform destroy -auto-approve
    
    # Verify destruction
    if [[ $(check_existing_resources) == "true" ]]; then
        log_error "Failed to destroy all resources"
    fi
    
    log_success "Infrastructure destroyed successfully"
}

# Update configurations for target state
update_configurations() {
    local target_state=$1
    log_info "Updating configurations for $target_state state..."
    
    # Update terraform workspace
    cd "${PROJECT_ROOT}/terraform"
    terraform workspace select "$target_state" || terraform workspace new "$target_state"
    
    # Update config.yaml
    python3 -c "
import yaml
with open('${PROJECT_ROOT}/config/config.yaml', 'r') as f:
    config = yaml.safe_load(f)
config['project']['environment'] = '$target_state'
with open('${PROJECT_ROOT}/config/config.yaml', 'w') as f:
    yaml.dump(config, f)
"
    
    # Validate updated configuration
    validate_configuration
    
    log_success "Configurations updated successfully"
}

# Deploy new infrastructure
deploy_infrastructure() {
    local target_state=$1
    log_info "Deploying $target_state infrastructure..."
    
    cd "${PROJECT_ROOT}/terraform"
    
    # Initialize and plan
    terraform init
    terraform plan -out=tfplan
    
    # Apply infrastructure
    terraform apply tfplan
    
    # Verify deployment
    if [[ $(check_existing_resources) != "true" ]]; then
        log_error "Failed to verify infrastructure deployment"
    fi
    
    log_success "Infrastructure deployed successfully"
}

# Configure application
configure_application() {
    local target_state=$1
    log_info "Configuring application for $target_state state..."
    
    # Update kubernetes configs
    cd "${PROJECT_ROOT}/kubernetes"
    
    # Apply appropriate overlay
    kubectl apply -k "overlays/${target_state}"
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pods \
        -l app=cloudsecdemo \
        -n cloudsecdemo \
        --timeout=300s
        
    log_success "Application configured successfully"
}

#############################################################################
# Main Function
#############################################################################

main() {
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 [secure|insecure] [--skip-backup] [--force]"
    fi

    local target_state=$1
    shift

    # Parse additional options
    local skip_backup=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup)
                skip_backup=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done

    # Validate target state
    case "$target_state" in
        secure|insecure) ;;
        *) log_error "Invalid state: $target_state" ;;
    esac

    # Check if resources exist
    if [[ $(check_existing_resources) == "true" ]]; then
        if [[ "$force" != "true" ]]; then
            log_warn "Existing infrastructure detected!"
            read -p "Are you sure you want to destroy and rebuild? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Operation cancelled by user"
            fi
        fi
        
        # Backup if needed
        if [[ "$skip_backup" != "true" ]]; then
            save_state
        fi
        
        # Destroy existing infrastructure
        destroy_infrastructure
    fi

    # Update configurations
    update_configurations "$target_state"

    # Deploy new infrastructure
    deploy_infrastructure "$target_state"

    # Configure application
    configure_application "$target_state"

    log_success "Full toggle to $target_state state completed successfully"
}

# Execute main function
main "$@"
