#!/bin/bash

#############################################################################
# Cloud Security Demo - Configuration Validator
# 
# This script validates the configuration files against the schema and
# performs additional security and sanity checks. It validates:
# - YAML syntax
# - JSON schema compliance
# - Environment variables
# - Security configurations
# - Resource naming
# - Network CIDR ranges
# - AWS-specific constraints
#
# Usage:
#   source ./scripts/utils/validate_config.sh
#   validate_configuration
#############################################################################

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/logger.sh"

#############################################################################
# Constants and Configurations
#############################################################################

# Configuration paths
readonly CONFIG_FILE="${PROJECT_ROOT}/config/config.yaml"
readonly SCHEMA_FILE="${PROJECT_ROOT}/config/schema/config_schema.json"
readonly ENV_FILE="${PROJECT_ROOT}/.env"

# Network constraints
readonly VALID_VPC_RANGES=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")
readonly MIN_SUBNET_SIZE=24
readonly MAX_SUBNET_SIZE=16

# Resource naming constraints
readonly MAX_RESOURCE_NAME_LENGTH=64
readonly RESOURCE_NAME_PATTERN="^[a-z0-9-]+$"

#############################################################################
# Utility Functions
#############################################################################

# Check if a CIDR is within a valid VPC range
is_valid_vpc_cidr() {
    local cidr=$1
    local ip=$(echo $cidr | cut -d/ -f1)
    local prefix=$(echo $cidr | cut -d/ -f2)
    
    for valid_range in "${VALID_VPC_RANGES[@]}"; do
        if python3 -c "
import ipaddress
test_net = ipaddress.ip_network('$cidr', strict=False)
valid_net = ipaddress.ip_network('$valid_range', strict=False)
print(1 if test_net.subnet_of(valid_net) else 0)
        " | grep -q "1"; then
            return 0
        fi
    done
    return 1
}

# Validate a resource name
is_valid_resource_name() {
    local name=$1
    if [[ ${#name} -gt $MAX_RESOURCE_NAME_LENGTH ]]; then
        return 1
    fi
    if ! [[ $name =~ $RESOURCE_NAME_PATTERN ]]; then
        return 1
    fi
    return 0
}

#############################################################################
# Validation Functions
#############################################################################

# Validate YAML syntax
validate_yaml_syntax() {
    log_debug "Validating YAML syntax..."
    
    if ! python3 -c "import yaml; yaml.safe_load(open('${CONFIG_FILE}'))" 2>/dev/null; then
        log_error "Invalid YAML syntax in configuration file"
    fi
    
    log_success "YAML syntax validation passed"
}

# Validate against JSON schema
validate_against_schema() {
    log_debug "Validating configuration against schema..."
    
    # Convert YAML to JSON for validation
    local temp_json=$(mktemp)
    python3 -c "
import yaml, json
with open('${CONFIG_FILE}') as f:
    config = yaml.safe_load(f)
with open('${temp_json}', 'w') as f:
    json.dump(config, f)
"
    
    # Validate using Python jsonschema
    if ! python3 -c "
import json, jsonschema
with open('${SCHEMA_FILE}') as f:
    schema = json.load(f)
with open('${temp_json}') as f:
    instance = json.load(f)
jsonschema.validate(instance=instance, schema=schema)
    "; then
        rm "${temp_json}"
        log_error "Configuration failed schema validation"
    fi
    
    rm "${temp_json}"
    log_success "Schema validation passed"
}

# Validate environment variables
validate_env_vars() {
    log_debug "Validating environment variables..."
    
    # Load environment variables
    if [[ -f "${ENV_FILE}" ]]; then
        set -a
        source "${ENV_FILE}"
        set +a
    else
        log_error "Environment file not found: ${ENV_FILE}"
    fi
    
    # Required variables
    local required_vars=(
        "AWS_REGION"
        "PROJECT_NAME"
        "ENVIRONMENT"
        "OWNER_EMAIL"
        "TERRAFORM_STATE_BUCKET"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
    fi
    
    # Validate AWS region format
    if ! [[ "${AWS_REGION}" =~ ^[a-z]{2}-[a-z]+-[0-9]{1}$ ]]; then
        log_error "Invalid AWS region format: ${AWS_REGION}"
    fi
    
    log_success "Environment variables validation passed"
}

# Validate network configuration
validate_network_config() {
    log_debug "Validating network configuration..."
    
    # Load configuration
    local vpc_cidr=$(python3 -c "
import yaml
config = yaml.safe_load(open('${CONFIG_FILE}'))
print(config['infrastructure']['vpc']['cidr'])
    ")
    
    # Validate VPC CIDR
    if ! is_valid_vpc_cidr "${vpc_cidr}"; then
        log_error "Invalid VPC CIDR range: ${vpc_cidr}"
    fi
    
    # Validate subnets
    python3 -c "
import yaml, ipaddress
config = yaml.safe_load(open('${CONFIG_FILE}'))
vpc_net = ipaddress.ip_network(config['infrastructure']['vpc']['cidr'])
for subnet_type in ['public', 'private']:
    for subnet in config['infrastructure']['vpc']['subnets'][subnet_type]:
        subnet_net = ipaddress.ip_network(subnet['cidr'])
        if not subnet_net.subnet_of(vpc_net):
            raise ValueError(f'Subnet {subnet['cidr']} is not within VPC CIDR')
        if subnet_net.prefixlen > ${MIN_SUBNET_SIZE}:
            raise ValueError(f'Subnet {subnet['cidr']} is too small')
        if subnet_net.prefixlen < ${MAX_SUBNET_SIZE}:
            raise ValueError(f'Subnet {subnet['cidr']} is too large')
    "
    
    log_success "Network configuration validation passed"
}

# Validate security configuration
validate_security_config() {
    log_debug "Validating security configuration..."
    
    local config_env=$(python3 -c "
import yaml
config = yaml.safe_load(open('${CONFIG_FILE}'))
print(config['project']['environment'])
    ")
    
    # Validate secure configuration
    if [[ "${config_env}" == "secure" ]]; then
        python3 -c "
import yaml
config = yaml.safe_load(open('${CONFIG_FILE}'))
secure = config['security_states']['secure']

assert secure['network']['enable_flow_logs'], 'Flow logs must be enabled in secure mode'
assert secure['storage']['s3']['enable_encryption'], 'S3 encryption must be enabled in secure mode'
assert secure['compute']['eks']['private_endpoint'], 'EKS private endpoint must be enabled in secure mode'
assert secure['database']['encryption_at_rest'], 'Database encryption must be enabled in secure mode'
assert secure['iam']['enforce_mfa'], 'MFA must be enforced in secure mode'
        "
    fi
    
    log_success "Security configuration validation passed"
}

# Validate resource names
validate_resource_names() {
    log_debug "Validating resource names..."
    
    # Load and validate resource names
    python3 -c "
import yaml
config = yaml.safe_load(open('${CONFIG_FILE}'))

def check_name(name, path):
    if len(name) > ${MAX_RESOURCE_NAME_LENGTH}:
        raise ValueError(f'Resource name too long at {path}: {name}')
    if not name.islower() or not all(c.isalnum() or c == '-' for c in name):
        raise ValueError(f'Invalid resource name format at {path}: {name}')

# Check project name
check_name(config['project']['name'], 'project.name')

# Check EKS node group names
for ng in config['infrastructure']['eks']['node_groups']:
    check_name(ng['name'], f'infrastructure.eks.node_groups[].name')

# Check application name
check_name(config['application']['name'], 'application.name')
    "
    
    log_success "Resource names validation passed"
}

#############################################################################
# Main Validation Function
#############################################################################

validate_configuration() {
    log_info "Starting configuration validation..."
    
    # Check if configuration files exist
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
    fi
    
    if [[ ! -f "${SCHEMA_FILE}" ]]; then
        log_error "Schema file not found: ${SCHEMA_FILE}"
    fi
    
    # Run all validations
    validate_yaml_syntax
    validate_against_schema
    validate_env_vars
    validate_network_config
    validate_security_config
    validate_resource_names
    
    log_success "Configuration validation completed successfully"
    return 0
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_configuration
fi
