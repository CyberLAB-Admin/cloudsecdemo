#!/bin/bash

#############################################################################
# Cloud Security Demo - Main Deployment Script
# 
# This script orchestrates the complete deployment process including:
# - Infrastructure deployment (Terraform)
# - Application deployment (Kubernetes)
# - Monitoring setup
# - Security state configuration
#
# Usage: ./deploy.sh [secure|insecure] [--force] [--no-monitoring]
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source common utilities
source "${PROJECT_ROOT}/scripts/utils/logger.sh"
source "${PROJECT_ROOT}/scripts/utils/aws_setup.sh"
source "${PROJECT_ROOT}/scripts/utils/validate_config.sh"

#############################################################################
# Configuration and Arguments
#############################################################################

# Default values
FORCE_DEPLOY=false
SKIP_MONITORING=false
ENVIRONMENT=""

# Parse arguments
parse_arguments() {
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 [secure|insecure] [--force] [--no-monitoring]"
    fi

    ENVIRONMENT=$1
    shift

    case "$ENVIRONMENT" in
        secure|insecure)
            ;;
        *)
            log_error "Environment must be 'secure' or 'insecure'"
            ;;
    esac

    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            --no-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done
}

#############################################################################
# Deployment Functions
#############################################################################

# Validate deployment prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check required tools
    local required_tools=("terraform" "kubectl" "aws")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Required tool not found: $tool"
        fi
    done

    # Validate AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "Invalid AWS credentials"
    fi

    # Validate configuration
    validate_configuration

    log_success "Prerequisites validation completed"
}

# Deploy infrastructure using Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure..."

    cd "${PROJECT_ROOT}/terraform"

    # Create DynamoDB table for state locking if it doesn't exist
    log_info "Checking DynamoDB table for state locking..."
    if ! aws dynamodb describe-table --table-name terraform-state-lock &>/dev/null; then
        log_info "Creating DynamoDB table for state locking..."
        aws dynamodb create-table \
            --table-name terraform-state-lock \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --tags Key=Project,Value=${PROJECT_NAME} || log_error "Failed to create DynamoDB table"
        
        # Wait for table to be active
        log_info "Waiting for DynamoDB table to be ready..."
        aws dynamodb wait table-exists --table-name terraform-state-lock
    fi

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init

    # Select workspace
    terraform workspace select -or-create "$ENVIRONMENT" || terraform workspace new "$ENVIRONMENT"

    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan -var="environment=${ENVIRONMENT}"

    # Apply deployment
    if [[ "$FORCE_DEPLOY" == "true" ]]; then
        terraform apply -auto-approve tfplan
    else
        log_warn "Review the plan above."
        read -p "Do you want to apply this plan? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled by user"
        fi
        terraform apply tfplan
    fi

    cd - > /dev/null

    log_success "Infrastructure deployment completed"
}

# Configure Kubernetes
setup_kubernetes() {
    log_info "Setting up Kubernetes..."

    # Update kubeconfig
    local cluster_name="${PROJECT_NAME}-cluster"
    aws eks update-kubeconfig --name "$cluster_name" --region "$AWS_REGION"

    # Verify connection
    if ! kubectl cluster-info; then
        log_error "Failed to connect to Kubernetes cluster"
    fi

    # Apply configurations
    log_info "Applying Kubernetes configurations..."
    kubectl apply -k "${PROJECT_ROOT}/kubernetes/overlays/${ENVIRONMENT}"

    # Wait for deployments
    kubectl wait --for=condition=available --timeout=300s \
        deployment -l app=cloudsecdemo -n cloudsecdemo

    log_success "Kubernetes setup completed"
}

# Deploy monitoring
deploy_monitoring() {
    if [[ "$SKIP_MONITORING" == "true" ]]; then
        log_warn "Skipping monitoring deployment"
        return
    fi

    log_info "Deploying monitoring components..."
    "${SCRIPT_DIR}/utils/monitor_deploy.sh"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."

    # Check infrastructure
    if ! terraform output -state="${PROJECT_ROOT}/terraform/terraform.tfstate" &>/dev/null; then
        log_error "Failed to validate infrastructure deployment"
    fi

    # Check Kubernetes deployments
    if ! kubectl get deployment -n cloudsecdemo -l app=cloudsecdemo &>/dev/null; then
        log_error "Failed to validate Kubernetes deployment"
    fi

    # Check monitoring
    if [[ "$SKIP_MONITORING" == "false" ]]; then
        local function_name="${PROJECT_NAME}-security-monitor"
        if ! aws lambda get-function --function-name "$function_name" &>/dev/null; then
            log_error "Failed to validate monitoring deployment"
        fi
    fi

    log_success "Deployment validation completed"
}

# Tag resources
tag_resources() {
    log_info "Tagging resources..."
    "${SCRIPT_DIR}/utils/resource_tagger.sh" \
        --project "$PROJECT_NAME" \
        --environment "$ENVIRONMENT"
}

#############################################################################
# Main Function
#############################################################################

main() {
    log_info "Starting deployment for environment: $ENVIRONMENT"

    # Parse command line arguments
    parse_arguments "$@"

    # Run deployment steps
    validate_prerequisites
    deploy_infrastructure
    setup_kubernetes
    deploy_monitoring
    tag_resources
    validate_deployment

    # Post-deployment configuration
    log_info "Running post-deployment configuration..."
    
    # Get MongoDB endpoint
    log_info "Getting MongoDB endpoint from Terraform..."
    DB_ENDPOINT=$(terraform output -json | jq -r '.database_endpoint.value')
    
    if [[ -z "$DB_ENDPOINT" ]]; then
        log_error "Failed to get MongoDB endpoint from Terraform output"
    fi

    # Update ConfigMap with MongoDB URI
    log_info "Updating Kubernetes ConfigMap..."
    MONGODB_URI="mongodb://${DB_ENDPOINT}/taskdb"
    
    kubectl get configmap cloudsecdemo-config -n cloudsecdemo -o yaml | \
        sed "s|MONGODB_URI:.*|MONGODB_URI: \"$MONGODB_URI\"|" | \
        kubectl apply -f -

    # Rollout restart to pick up new config
    log_info "Restarting deployment to pick up new configuration..."
    kubectl rollout restart deployment cloudsecdemo-app -n cloudsecdemo

    # Wait for rollout to complete
    log_info "Waiting for deployment rollout to complete..."
    kubectl rollout status deployment cloudsecdemo-app -n cloudsecdemo --timeout=300s

    # Get service URL
    log_info "Waiting for LoadBalancer external IP/hostname..."
    for i in {1..30}; do
        EXTERNAL_IP=$(kubectl get svc cloudsecdemo-service -n cloudsecdemo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        if [[ -n "$EXTERNAL_IP" ]]; then
            break
        fi
        log_info "Waiting for LoadBalancer to be ready... ($i/30)"
        sleep 10
    done

    if [[ -z "$EXTERNAL_IP" ]]; then
        log_error "Failed to get LoadBalancer external IP/hostname"
    fi

    log_success "Deployment completed successfully!"

    # Display access information
    cat <<EOF

Deployment Summary:
------------------
Environment: $ENVIRONMENT
Kubernetes Context: $(kubectl config current-context)
Application URL: http://${EXTERNAL_IP}
MongoDB Endpoint: ${DB_ENDPOINT}
Monitoring Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${PROJECT_NAME}-security

Next Steps:
1. Access the application at: http://${EXTERNAL_IP}
2. Check the monitoring dashboard
3. Review the security state using the monitor function

For more information, see the documentation in docs/
EOF

    # Save access information to file
    cat > access-info.txt << EOF
Access Information
-----------------
Application URL: http://${EXTERNAL_IP}
MongoDB Endpoint: ${DB_ENDPOINT}
Monitoring Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${PROJECT_NAME}-security
EOF

    log_info "Access information saved to access-info.txt"
}

# Execute main function
main "$@"