#!/bin/bash

#############################################################################
# Cloud Security Demo - Security State Toggle Controller
# 
# This script controls the switching between secure and insecure states.
# It provides two methods of toggling:
# 1. Quick toggle: Changes only configurations
# 2. Full toggle: Completely rebuilds the infrastructure
#
# Usage: ./toggle.sh [quick|full] [secure|insecure] [--force] [--no-backup]
#
# Examples:
#   ./toggle.sh quick secure    # Quick switch to secure state
#   ./toggle.sh full insecure   # Full rebuild in insecure state
#   ./toggle.sh quick secure --force  # Force quick switch without confirmation
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source utility scripts
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/security_validator.sh"

#############################################################################
# Global Variables and Constants
#############################################################################

# Toggle modes
readonly MODE_QUICK="quick"
readonly MODE_FULL="full"

# States
readonly STATE_SECURE="secure"
readonly STATE_INSECURE="insecure"

# Default values
FORCE_TOGGLE=false
BACKUP_ENABLED=true

#############################################################################
# Helper Functions
#############################################################################

print_usage() {
    cat <<EOF
Usage: $0 [quick|full] [secure|insecure] [options]

Toggle Modes:
    quick       - Change only configurations
    full        - Complete infrastructure rebuild

States:
    secure      - Switch to secure configuration
    insecure    - Switch to insecure configuration

Options:
    --force     - Skip confirmation prompts
    --no-backup - Skip state backup
    --help      - Show this help message

Examples:
    $0 quick secure     # Quick switch to secure state
    $0 full insecure    # Full rebuild in insecure state
EOF
    exit 1
}

# Validate arguments
validate_args() {
    if [[ $# -lt 2 ]]; then
        print_usage
    fi

    # Validate toggle mode
    case "$1" in
        $MODE_QUICK|$MODE_FULL) ;;
        *) log_error "Invalid toggle mode: $1" ;;
    esac

    # Validate state
    case "$2" in
        $STATE_SECURE|$STATE_INSECURE) ;;
        *) log_error "Invalid state: $2" ;;
    esac
}

# Create state backup
create_backup() {
    if [[ "$BACKUP_ENABLED" == "true" ]]; then
        log_info "Creating state backup..."
        
        local backup_dir="${PROJECT_ROOT}/backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"

        # Backup terraform state
        if [[ -f "${PROJECT_ROOT}/terraform/terraform.tfstate" ]]; then
            cp "${PROJECT_ROOT}/terraform/terraform.tfstate" "$backup_dir/"
        fi

        # Backup configuration
        cp "${PROJECT_ROOT}/config/config.yaml" "$backup_dir/"
        
        log_success "Backup created in: $backup_dir"
    else
        log_warn "State backup is disabled"
    fi
}

# Confirm toggle
confirm_toggle() {
    local mode=$1
    local target_state=$2
    
    if [[ "$FORCE_TOGGLE" == "true" ]]; then
        return 0
    fi

    local warning_message="You are about to switch to $target_state state using $mode toggle."
    if [[ "$mode" == "$MODE_FULL" ]]; then
        warning_message+="\nThis will destroy and recreate all infrastructure!"
    fi
    
    echo -e "\n${warning_message}\n"
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Toggle cancelled by user"
    fi
}

#############################################################################
# Toggle Functions
#############################################################################

execute_quick_toggle() {
    local target_state=$1
    log_info "Executing quick toggle to $target_state state..."
    
    "${SCRIPT_DIR}/quick-toggle.sh" "$target_state"
}

execute_full_toggle() {
    local target_state=$1
    log_info "Executing full toggle to $target_state state..."
    
    "${SCRIPT_DIR}/full-toggle.sh" "$target_state"
}

#############################################################################
# Main Function
#############################################################################

main() {
    local toggle_mode=$1
    local target_state=$2
    shift 2

    # Parse additional options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_TOGGLE=true
                shift
                ;;
            --no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            --help)
                print_usage
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done

    # Validate current state
    validate_current_state

    # Confirm action
    confirm_toggle "$toggle_mode" "$target_state"

    # Create backup
    create_backup

    # Execute toggle based on mode
    case "$toggle_mode" in
        $MODE_QUICK)
            execute_quick_toggle "$target_state"
            ;;
        $MODE_FULL)
            execute_full_toggle "$target_state"
            ;;
    esac

    # Validate new state
    validate_target_state "$target_state"

    log_success "Successfully toggled to $target_state state using $toggle_mode mode"
}

# Execute main function with all arguments
main "$@"
