#!/bin/bash

# EC2 Auto-Shutdown Deployment Script
# This script helps with initial setup and manual deployments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  setup-iam        Set up IAM roles for cross-account access"
    echo "  package-lambda   Package Lambda function for deployment"
    echo "  deploy           Deploy to specific environment"
    echo "  test-lambda      Test Lambda function locally"
    echo "  validate         Validate Terraform configuration"
    echo ""
    echo "Options:"
    echo "  --environment    Environment to deploy to (production, development, staging)"
    echo "  --account-id     AWS Account ID"
    echo "  --region         AWS Region"
    echo "  --dry-run        Enable dry run mode"
    echo ""
    echo "Examples:"
    echo "  $0 setup-iam --account-id 123456789012"
    echo "  $0 deploy --environment production"
    echo "  $0 package-lambda"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_dependencies() {
    local deps=("terraform" "aws" "python3" "zip")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' is not installed"
        fi
    done
    
    log "All dependencies are available"
}

setup_iam() {
    local account_id="$1"
    
    if [[ -z "$account_id" ]]; then
        error "Account ID is required for IAM setup"
    fi
    
    log "Setting up IAM roles for account: $account_id"
    
    # Check if this is the automation account
    current_account=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ "$current_account" == "$account_id" ]]; then
        log "Setting up automation account IAM role"
        cd "$PROJECT_ROOT/terraform"
        terraform init
        terraform plan -var="is_automation_account=true" -var="target_account_id=$account_id"
        terraform apply -var="is_automation_account=true" -var="target_account_id=$account_id"
    else
        log "Setting up cross-account IAM role"
        cd "$PROJECT_ROOT/terraform"
        terraform init
        terraform plan -var="is_automation_account=false" -var="target_account_id=$account_id"
        terraform apply -var="is_automation_account=false" -var="target_account_id=$account_id"
    fi
    
    log "IAM setup completed"
}

package_lambda() {
    log "Packaging Lambda function"
    
    cd "$PROJECT_ROOT/lambda"
    
    if [[ -f "package.sh" ]]; then
        ./package.sh
    else
        error "Lambda package script not found"
    fi
    
    log "Lambda function packaged successfully"
}

validate_terraform() {
    log "Validating Terraform configuration"
    
    cd "$PROJECT_ROOT/terraform"
    terraform fmt -check=true -recursive
    terraform init -backend=false
    terraform validate
    
    log "Terraform configuration is valid"
}

deploy_environment() {
    local environment="$1"
    local account_id="$2"
    local region="$3"
    local dry_run="$4"
    
    if [[ -z "$environment" ]]; then
        error "Environment is required for deployment"
    fi
    
    log "Deploying to environment: $environment"
    
    # Package Lambda first
    package_lambda
    
    # Read configuration
    config_file="$PROJECT_ROOT/config/ou-accounts.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
    fi
    
    # Deploy using Terraform
    cd "$PROJECT_ROOT/terraform"
    
    if [[ -n "$account_id" && -n "$region" ]]; then
        # Manual deployment to specific account/region
        log "Deploying to Account: $account_id, Region: $region"
        
        terraform init \
            -backend-config="bucket=terraform-state-$account_id" \
            -backend-config="key=ec2-shutdown/$region/terraform.tfstate" \
            -backend-config="region=$region"
        
        terraform plan \
            -var="target_account_id=$account_id" \
            -var="target_region=$region" \
            -var="environment=$environment" \
            -var="lambda_package_path=../lambda/ec2-shutdown-lambda.zip" \
            ${dry_run:+-var="dry_run=true"}
        
        read -p "Apply changes? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            terraform apply \
                -var="target_account_id=$account_id" \
                -var="target_region=$region" \
                -var="environment=$environment" \
                -var="lambda_package_path=../lambda/ec2-shutdown-lambda.zip" \
                ${dry_run:+-var="dry_run=true"}
        fi
    else
        # Deploy to all accounts in environment (requires Python/YAML parsing)
        python3 << EOF
import yaml
import os
import subprocess

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

for ou in config['organizational_units']:
    if ou['name'] == '$environment':
        for account in ou['accounts']:
            for region in account['regions']:
                print(f"Deploying to Account: {account['account_id']}, Region: {region}")
                
                # Run terraform commands
                subprocess.run([
                    'terraform', 'init',
                    f'-backend-config=bucket=terraform-state-{account["account_id"]}',
                    f'-backend-config=key=ec2-shutdown/{region}/terraform.tfstate',
                    f'-backend-config=region={region}'
                ], check=True)
                
                subprocess.run([
                    'terraform', 'apply', '-auto-approve',
                    f'-var=target_account_id={account["account_id"]}',
                    f'-var=target_region={region}',
                    f'-var=environment=$environment',
                    f'-var=cross_account_role_name={account["role_name"]}',
                    f'-var=lambda_package_path=../lambda/ec2-shutdown-lambda.zip'
                ] + (['${dry_run:+-var=dry_run=true}'] if '$dry_run' else []), check=True)
EOF
    fi
    
    log "Deployment completed"
}

test_lambda() {
    log "Testing Lambda function locally"
    
    cd "$PROJECT_ROOT/lambda/src"
    
    # Create test event
    cat > test_event.json << 'EOF'
{
    "source": "aws.events",
    "detail-type": "Scheduled Event",
    "detail": {}
}
EOF
    
    # Run Lambda function
    python3 -c "
import ec2_shutdown
import json

with open('test_event.json', 'r') as f:
    event = json.load(f)

class MockContext:
    def __init__(self):
        self.aws_request_id = 'test-request-id'
        self.log_group_name = '/aws/lambda/test'
        self.log_stream_name = 'test-stream'
        self.function_name = 'test-function'
        self.memory_limit_in_mb = 256
        self.function_version = '\$LATEST'
        self.invoked_function_arn = 'arn:aws:lambda:us-east-1:123456789012:function:test'

context = MockContext()
result = ec2_shutdown.lambda_handler(event, context)
print(json.dumps(result, indent=2))
"
    
    rm test_event.json
    log "Lambda test completed"
}

# Parse command line arguments
COMMAND=""
ENVIRONMENT=""
ACCOUNT_ID=""
REGION=""
DRY_RUN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        setup-iam|package-lambda|deploy|test-lambda|validate)
            COMMAND="$1"
            shift
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --account-id)
            ACCOUNT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Check dependencies
check_dependencies

# Execute command
case "$COMMAND" in
    setup-iam)
        setup_iam "$ACCOUNT_ID"
        ;;
    package-lambda)
        package_lambda
        ;;
    deploy)
        deploy_environment "$ENVIRONMENT" "$ACCOUNT_ID" "$REGION" "$DRY_RUN"
        ;;
    test-lambda)
        test_lambda
        ;;
    validate)
        validate_terraform
        ;;
    "")
        error "No command specified. Use --help for usage information."
        ;;
    *)
        error "Unknown command: $COMMAND"
        ;;
esac