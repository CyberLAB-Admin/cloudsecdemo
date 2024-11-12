#!/bin/bash

#############################################################################
# Cloud Security Demo - Logging Utility
# 
# This script provides consistent logging functions across all scripts in the
# project. It includes:
# - Colored output for different message types
# - Log levels (DEBUG, INFO, WARN, ERROR)
# - Optional quiet mode
# - Timestamp prefixing
# - Log file output option
#
# Usage:
#   source ./scripts/utils/logger.sh
#   log_info "Starting process"
#   log_error "Something went wrong"
#############################################################################

# Exit on undefined variables
set -u

#############################################################################
# Global Variables and Constants
#############################################################################

# Color definitions
LOG_COLOR_RED='\033[0;31m'
LOG_COLOR_GREEN='\033[0;32m'
LOG_COLOR_YELLOW='\033[1;33m'
LOG_COLOR_BLUE='\033[0;34m'
LOG_COLOR_NC='\033[0m' # No Color

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Default configuration
LOG_LEVEL=${LOG_LEVEL:-1}        # Default to INFO
LOG_TO_FILE=${LOG_TO_FILE:-false}
LOG_FILE=${LOG_FILE:-"cloudsecdemo.log"}
QUIET_MODE=${QUIET_MODE:-false}

#############################################################################
# Utility Functions
#############################################################################

# Get current timestamp
_get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Internal logging function
_log() {
    local level=$1
    local color=$2
    local message=$3
    local timestamp=$(_get_timestamp)
    
    # Create log message
    local log_message="[${timestamp}] [${level}] ${message}"
    
    # Write to file if enabled
    if [[ "${LOG_TO_FILE}" == "true" ]]; then
        echo "${log_message}" >> "${LOG_FILE}"
    fi
    
    # Write to console if not in quiet mode
    if [[ "${QUIET_MODE}" == "false" ]]; then
        echo -e "${color}${log_message}${LOG_COLOR_NC}" >&2
    fi
}

#############################################################################
# Public Logging Functions
#############################################################################

# Debug level logging
log_debug() {
    if [[ ${LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]]; then
        _log "DEBUG" "${LOG_COLOR_BLUE}" "$1"
    fi
}

# Info level logging
log_info() {
    if [[ ${LOG_LEVEL} -le ${LOG_LEVEL_INFO} ]]; then
        _log "INFO" "${LOG_COLOR_GREEN}" "$1"
    fi
}

# Warning level logging
log_warn() {
    if [[ ${LOG_LEVEL} -le ${LOG_LEVEL_WARN} ]]; then
        _log "WARN" "${LOG_COLOR_YELLOW}" "$1"
    fi
}

# Error level logging
log_error() {
    if [[ ${LOG_LEVEL} -le ${LOG_LEVEL_ERROR} ]]; then
        _log "ERROR" "${LOG_COLOR_RED}" "$1"
        # Return error code if provided as second parameter
        if [[ $# -gt 1 ]]; then
            exit "$2"
        else
            exit 1
        fi
    fi
}

# Success message logging
log_success() {
    _log "SUCCESS" "${LOG_COLOR_GREEN}" "$1"
}

#############################################################################
# Configuration Functions
#############################################################################

# Enable file logging
enable_file_logging() {
    LOG_TO_FILE=true
    # Create log directory if it doesn't exist
    local log_dir=$(dirname "${LOG_FILE}")
    [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}"
    touch "${LOG_FILE}"
    log_debug "File logging enabled: ${LOG_FILE}"
}

# Set log level
set_log_level() {
    case "${1,,}" in
        debug) LOG_LEVEL=${LOG_LEVEL_DEBUG} ;;
        info)  LOG_LEVEL=${LOG_LEVEL_INFO} ;;
        warn)  LOG_LEVEL=${LOG_LEVEL_WARN} ;;
        error) LOG_LEVEL=${LOG_LEVEL_ERROR} ;;
        *)     log_error "Invalid log level: $1" ;;
    esac
    log_debug "Log level set to: $1"
}

# Enable quiet mode
enable_quiet_mode() {
    QUIET_MODE=true
    log_debug "Quiet mode enabled"
}

#############################################################################
# Usage Example
#############################################################################
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#     # Script is being run directly, show example usage
#     log_debug "This is a debug message"
#     log_info "This is an info message"
#     log_warn "This is a warning message"
#     log_error "This is an error message"
# fi
