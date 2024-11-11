#!/bin/bash

#############################################################################
# Cloud Security Demo - Monitoring Deployment Utility
# 
# This script handles the deployment of monitoring components including:
# - Lambda function packaging and deployment
# - CloudWatch configuration
# - SNS topic setup
# - Alarm configuration
# - Dashboard creation
#############################################################################

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/../.." && pwd )"

# Source common utilities
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/aws_setup.sh"

#############################################################################
# Configuration
#############################################################################

LAMBDA_DIR="${PROJECT_ROOT}/monitoring/lambda"
FUNCTION_NAME="${PROJECT_NAME}-security-monitor"
LAMBDA_ROLE_NAME="${PROJECT_NAME}-monitor-role"
LAMBDA_TIMEOUT=300
LAMBDA_MEMORY=256

#############################################################################
# Lambda Deployment Functions
#############################################################################

create_lambda_role() {
    log_info "Creating Lambda execution role..."
    
    # Create role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }]
        }' || log_error "Failed to create Lambda role"

    # Attach policies
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

    # Custom policy for monitoring
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name "monitoring-permissions" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "ec2:Describe*",
                        "s3:Get*",
                        "s3:List*",
                        "iam:Get*",
                        "iam:List*",
                        "eks:Describe*",
                        "eks:List*",
                        "cloudwatch:PutMetricData",
                        "sns:Publish"
                    ],
                    "Resource": "*"
                }
            ]
        }'

    # Wait for role to propagate
    sleep 10
}

package_lambda() {
    log_info "Packaging Lambda function..."
    
    cd "${LAMBDA_DIR}"
    
    # Install dependencies
    npm install --production
    
    # Create deployment package
    zip -r function.zip ./* -x "*.git*" "*.test.js" "*.md"
    
    cd - > /dev/null
}

deploy_lambda() {
    log_info "Deploying Lambda function..."
    
    local role_arn=$(aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" --query 'Role.Arn' --output text)
    
    # Check if function exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        # Update existing function
        aws lambda update-function-code \
            --function-name "${FUNCTION_NAME}" \
            --zip-file "fileb://${LAMBDA_DIR}/function.zip"
        
        aws lambda update-function-configuration \
            --function-name "${FUNCTION_NAME}" \
            --runtime "nodejs16.x" \
            --handler "index.handler" \
            --role "${role_arn}" \
            --timeout "${LAMBDA_TIMEOUT}" \
            --memory-size "${LAMBDA_MEMORY}" \
            --environment "Variables={
                PROJECT_NAME=${PROJECT_NAME},
                ENVIRONMENT=${ENVIRONMENT},
                SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
            }"
    else
        # Create new function
        aws lambda create-function \
            --function-name "${FUNCTION_NAME}" \
            --runtime "nodejs16.x" \
            --handler "index.handler" \
            --role "${role_arn}" \
            --timeout "${LAMBDA_TIMEOUT}" \
            --memory-size "${LAMBDA_MEMORY}" \
            --zip-file "fileb://${LAMBDA_DIR}/function.zip" \
            --environment "Variables={
                PROJECT_NAME=${PROJECT_NAME},
                ENVIRONMENT=${ENVIRONMENT},
                SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
            }"
    fi
}

#############################################################################
# CloudWatch Configuration Functions
#############################################################################

setup_cloudwatch() {
    log_info "Setting up CloudWatch resources..."
    
    # Create log group
    aws logs create-log-group \
        --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
        --tags "Project=${PROJECT_NAME},Environment=${ENVIRONMENT}"
    
    # Set retention policy
    aws logs put-retention-policy \
        --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
        --retention-in-days 30
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${PROJECT_NAME}-security" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["CloudSecDemo", "SecurityCheckFailures", "Environment", "'"${ENVIRONMENT}"'"]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'"${AWS_REGION}"'",
                        "title": "Security Check Failures"
                    }
                }
            ]
        }'
}

#############################################################################
# SNS Configuration Functions
#############################################################################

setup_sns() {
    log_info "Setting up SNS topic..."
    
    # Create topic
    local topic_arn=$(aws sns create-topic \
        --name "${PROJECT_NAME}-alerts" \
        --tags "Key=Project,Value=${PROJECT_NAME}" "Key=Environment,Value=${ENVIRONMENT}" \
        --query 'TopicArn' --output text)
    
    echo "export SNS_TOPIC_ARN=${topic_arn}"
    
    # Add subscription if email provided
    if [[ -n "${ALERT_EMAIL}" ]]; then
        aws sns subscribe \
            --topic-arn "${topic_arn}" \
            --protocol email \
            --notification-endpoint "${ALERT_EMAIL}"
        
        log_info "Please confirm the subscription in your email"
    fi
}

#############################################################################
# Alarm Configuration Functions
#############################################################################

setup_alarms() {
    log_info "Setting up CloudWatch alarms..."
    
    # Create alarm for security check failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-security-failures" \
        --alarm-description "Alert on security check failures" \
        --metric-name "SecurityCheckFailures" \
        --namespace "CloudSecDemo" \
        --statistic Sum \
        --period 300 \
        --threshold 0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions "Name=Environment,Value=${ENVIRONMENT}" \
        --tags "Key=Project,Value=${PROJECT_NAME}" "Key=Environment,Value=${ENVIRONMENT}"
}

#############################################################################
# Main Function
#############################################################################

main() {
    log_info "Starting monitoring deployment..."
    
    # Validate environment
    if [[ -z "${PROJECT_NAME}" ]] || [[ -z "${ENVIRONMENT}" ]]; then
        log_error "PROJECT_NAME and ENVIRONMENT must be set"
    }
    
    # Setup SNS first for notifications
    setup_sns
    
    # Create and deploy Lambda function
    create_lambda_role
    package_lambda
    deploy_lambda
    
    # Setup monitoring resources
    setup_cloudwatch
    setup_alarms
    
    log_success "Monitoring deployment completed successfully!"
    
    # Display next steps
    cat <<EOF

Next Steps:
1. Check your email and confirm the SNS subscription
2. View the CloudWatch dashboard: ${PROJECT_NAME}-security
3. Test the monitoring by running:
   aws lambda invoke --function-name ${FUNCTION_NAME} response.json

For more information, check the CloudWatch logs and metrics.
EOF
}

# Run main function
main "$@"
