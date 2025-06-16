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
    echo "  deploy-account   Deploy to specific account"
    echo "  test-lambda      Test Lambda function locally"
    echo "  validate         Validate Terraform configuration"
    echo ""
    echo "Options:"
    echo "  --account-name   Account name (prod-main, prod-eu, dev-main, dev-sandbox, staging-main)"
    echo "  --dry-run        Enable dry run mode"
    echo ""
    echo "Examples:"
    echo "  $0 setup-iam --account-name prod-main"
    echo "  $0 deploy-account --account-name prod-main"
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

get_account_id() {
    local account_name="$1"
    
    if [[ -z "$account_name" ]]; then
        error "Account name is required"
    fi
    
    # Parse ou-accounts.yaml to get account ID
    if ! command -v python3 &> /dev/null; then
        error "Python3 is required to parse configuration file"
    fi
    
    local account_id=$(python3 -c "
import yaml
import sys

try:
    with open('$PROJECT_ROOT/config/ou-accounts.yaml', 'r') as f:
        config = yaml.safe_load(f)
    
    for ou in config['organizational_units']:
        for account in ou['accounts']:
            if account['account_name'] == '$account_name':
                print(account['account_id'])
                sys.exit(0)
    
    print('', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error parsing config: {e}', file=sys.stderr)
    sys.exit(1)
")
    
    if [[ -z "$account_id" ]]; then
        error "Account name '$account_name' not found in config/ou-accounts.yaml"
    fi
    
    echo "$account_id"
}

setup_iam() {
    local account_name="$1"
    
    if [[ -z "$account_name" ]]; then
        error "Account name is required for IAM setup"
    fi
    
    # Get account ID from account name
    local account_id=$(get_account_id "$account_name")
    
    log "Setting up IAM roles for account: $account_name ($account_id)"
    
    # Check if this is the automation account
    current_account=$(aws sts get-caller-identity --query Account --output text)
    
    # Validate account directory exists
    local account_dir="$PROJECT_ROOT/accounts/$account_name"
    if [[ ! -d "$account_dir" ]]; then
        error "Account directory not found: $account_dir"
    fi
    
    if [[ "$current_account" == "$account_id" ]]; then
        log "Setting up automation account IAM role"
        cd "$account_dir"
        terraform init
        terraform plan -var="is_automation_account=true" -var="target_account_id=$account_id"
        terraform apply -var="is_automation_account=true" -var="target_account_id=$account_id"
    else
        log "Setting up cross-account IAM role"
        cd "$account_dir"
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

deploy_account() {
    local account_name="$1"
    local dry_run="$2"
    
    if [[ -z "$account_name" ]]; then
        error "Account name is required for deployment"
    fi
    
    # Validate account name
    local account_dir="$PROJECT_ROOT/accounts/$account_name"
    if [[ ! -d "$account_dir" ]]; then
        error "Account directory not found: $account_dir"
    fi
    
    log "Deploying to account: $account_name"
    
    # Package Lambda first
    package_lambda
    
    # Deploy using Terraform
    cd "$account_dir"
    
    log "Initializing Terraform..."
    terraform init
    
    log "Planning Terraform changes..."
    terraform plan ${dry_run:+-var="dry_run=true"}
    
    read -p "Apply changes? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Applying Terraform changes..."
        terraform apply ${dry_run:+-var="dry_run=true"}
    else
        log "Deployment cancelled"
        return 0
    fi
    
    log "Deployment completed for $account_name"
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
ACCOUNT_NAME=""
DRY_RUN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        setup-iam|package-lambda|deploy-account|test-lambda|validate)
            COMMAND="$1"
            shift
            ;;
        --account-name)
            ACCOUNT_NAME="$2"
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
        if [[ -z "$ACCOUNT_NAME" ]]; then
            error "Account name is required for IAM setup"
        fi
        setup_iam "$ACCOUNT_NAME"
        ;;
    package-lambda)
        package_lambda
        ;;
    deploy-account)
        deploy_account "$ACCOUNT_NAME" "$DRY_RUN"
        ;;
    test-lambda)
        test_lambda
        ;;
    validate)
        if [[ -n "$ACCOUNT_NAME" ]]; then
            cd "$PROJECT_ROOT/accounts/$ACCOUNT_NAME" && terraform validate
        else
            validate_terraform
        fi
        ;;
    "")
        error "No command specified. Use --help for usage information."
        ;;
    *)
        error "Unknown command: $COMMAND"
        ;;
esac