# EC2 Auto-Shutdown Deployment Guide

This guide provides detailed instructions for deploying the EC2 auto-shutdown solution to multiple AWS accounts using the new account-specific directory structure.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Manual Deployment](#manual-deployment)
- [Automated Deployment](#automated-deployment)
- [CI/CD Pipeline Setup](#cicd-pipeline-setup)
- [State Management](#state-management)
- [Troubleshooting](#troubleshooting)

## Overview

The solution is now organized into separate directories for each AWS account, allowing independent deployment and state management. Each account has its own:
- Terraform configuration files
- S3 backend state configuration
- Account-specific variables

## Prerequisites

### Required Tools
- Terraform >= 1.0
- AWS CLI v2
- Python 3.x
- zip utility
- make (for using Makefile)

### AWS Configuration
1. **S3 Buckets for State Storage**: Create S3 buckets in each target account:
   ```bash
   # For each account, create a bucket named: terraform-state-{ACCOUNT_ID}
   aws s3 mb s3://terraform-state-111111111111 --region us-east-1  # prod-main
   aws s3 mb s3://terraform-state-222222222222 --region eu-west-1  # prod-eu
   aws s3 mb s3://terraform-state-333333333333 --region us-east-1  # dev-main
   aws s3 mb s3://terraform-state-444444444444 --region us-east-1  # dev-sandbox
   aws s3 mb s3://terraform-state-555555555555 --region us-east-1  # staging-main
   ```

2. **IAM Roles**: Set up cross-account IAM roles in each target account named `EC2ShutdownRole` with necessary permissions.

3. **AWS CLI Profiles**: Configure AWS CLI profiles for cross-account access or ensure proper credentials are available.

## Directory Structure

```
ec2-multi-ou-idle-shutdown/
├── accounts/
│   ├── prod-main/              # Production main account (111111111111)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tf        # S3 backend config
│   │   ├── terraform.tfvars    # Account-specific variables
│   │   └── iam-setup.tf
│   ├── prod-eu/                # Production EU account (222222222222)
│   ├── dev-main/               # Development main account (333333333333)
│   ├── dev-sandbox/            # Development sandbox account (444444444444)
│   └── staging-main/           # Staging account (555555555555)
├── lambda/
│   ├── src/
│   ├── requirements.txt
│   └── package.sh
├── config/
│   └── ou-accounts.yaml
├── scripts/
│   └── deploy.sh
├── Makefile
└── DEPLOYMENT.md
```

## Manual Deployment

### Method 1: Using Makefile (Recommended)

1. **Package Lambda Function**:
   ```bash
   make package-lambda
   ```

2. **Deploy to Specific Account**:
   ```bash
   # Initialize Terraform
   make init-prod-main
   
   # Plan deployment
   make plan-prod-main
   
   # Apply changes
   make apply-prod-main
   ```

3. **Available Makefile Targets**:
   ```bash
   # Package Lambda
   make package-lambda
   
   # Initialize accounts
   make init-prod-main
   make init-prod-eu
   make init-dev-main
   make init-dev-sandbox
   make init-staging-main
   
   # Plan deployments
   make plan-prod-main
   make plan-prod-eu
   make plan-dev-main
   make plan-dev-sandbox
   make plan-staging-main
   
   # Apply deployments
   make apply-prod-main
   make apply-prod-eu
   make apply-dev-main
   make apply-dev-sandbox
   make apply-staging-main
   
   # Destroy resources
   make destroy-prod-main
   make destroy-prod-eu
   make destroy-dev-main
   make destroy-dev-sandbox
   make destroy-staging-main
   
   # Validate configurations
   make validate-prod-main
   make validate-prod-eu
   make validate-dev-main
   make validate-dev-sandbox
   make validate-staging-main
   
   # Format all Terraform files
   make fmt
   
   # Check all configurations
   make check
   
   # Clean temporary files
   make clean
   ```

### Method 2: Using Deployment Script

1. **Deploy to Specific Account**:
   ```bash
   ./scripts/deploy.sh deploy-account --account-name prod-main
   ```

2. **Deploy with Dry Run**:
   ```bash
   ./scripts/deploy.sh deploy-account --account-name prod-main --dry-run
   ```

3. **Other Script Commands**:
   ```bash
   # Package Lambda
   ./scripts/deploy.sh package-lambda
   
   # Setup IAM for specific account
   ./scripts/deploy.sh setup-iam --account-name prod-main
   
   # Test Lambda locally
   ./scripts/deploy.sh test-lambda
   
   # Validate specific account
   ./scripts/deploy.sh validate --account-name prod-main
   ```

### Method 3: Direct Terraform Commands

1. **Navigate to Account Directory**:
   ```bash
   cd accounts/prod-main
   ```

2. **Package Lambda** (from project root):
   ```bash
   cd ../../lambda && ./package.sh && cd ../accounts/prod-main
   ```

3. **Run Terraform Commands**:
   ```bash
   # Initialize
   terraform init
   
   # Plan
   terraform plan
   
   # Apply
   terraform apply
   
   # Destroy (when needed)
   terraform destroy
   ```

## Automated Deployment

### GitHub Actions Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy EC2 Auto-Shutdown

on:
  push:
    branches: [main]
    paths:
      - 'accounts/**'
      - 'lambda/**'
  pull_request:
    branches: [main]
    paths:
      - 'accounts/**'
      - 'lambda/**'
  workflow_dispatch:
    inputs:
      account_name:
        description: 'Account to deploy (leave empty for all)'
        required: false
        type: choice
        options:
          - ''
          - 'prod-main'
          - 'prod-eu'
          - 'dev-main'
          - 'dev-sandbox'
          - 'staging-main'
      action:
        description: 'Action to perform'
        required: true
        type: choice
        options:
          - 'plan'
          - 'apply'
          - 'destroy'

env:
  TF_VERSION: '1.5.0'

jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'
      
      - name: Package Lambda
        run: |
          cd lambda
          ./package.sh
      
      - name: Upload Lambda Package
        uses: actions/upload-artifact@v3
        with:
          name: lambda-package
          path: lambda/ec2-shutdown-lambda.zip

  deploy:
    needs: package
    runs-on: ubuntu-latest
    strategy:
      matrix:
        account: 
          - name: prod-main
            aws_role: arn:aws:iam::111111111111:role/GitHubActionsRole
          - name: prod-eu
            aws_role: arn:aws:iam::222222222222:role/GitHubActionsRole
          - name: dev-main
            aws_role: arn:aws:iam::333333333333:role/GitHubActionsRole
          - name: dev-sandbox
            aws_role: arn:aws:iam::444444444444:role/GitHubActionsRole
          - name: staging-main
            aws_role: arn:aws:iam::555555555555:role/GitHubActionsRole
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Download Lambda Package
        uses: actions/download-artifact@v3
        with:
          name: lambda-package
          path: lambda/
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ matrix.account.aws_role }}
          aws-region: us-east-1
          role-session-name: GitHubActions-${{ matrix.account.name }}
      
      - name: Terraform Init
        run: |
          cd accounts/${{ matrix.account.name }}
          terraform init
      
      - name: Terraform Plan
        run: |
          cd accounts/${{ matrix.account.name }}
          terraform plan -out=tfplan
        if: github.event_name == 'pull_request' || github.event.inputs.action == 'plan'
      
      - name: Terraform Apply
        run: |
          cd accounts/${{ matrix.account.name }}
          terraform apply -auto-approve
        if: github.ref == 'refs/heads/main' && github.event_name == 'push' || github.event.inputs.action == 'apply'
      
      - name: Terraform Destroy
        run: |
          cd accounts/${{ matrix.account.name }}
          terraform destroy -auto-approve
        if: github.event.inputs.action == 'destroy'

  deploy-single:
    needs: package
    runs-on: ubuntu-latest
    if: github.event.inputs.account_name != ''
    steps:
      - uses: actions/checkout@v4
      
      - name: Download Lambda Package
        uses: actions/download-artifact@v3
        with:
          name: lambda-package
          path: lambda/
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Get Account Role
        id: account-role
        run: |
          case "${{ github.event.inputs.account_name }}" in
            "prod-main") echo "role=arn:aws:iam::111111111111:role/GitHubActionsRole" >> $GITHUB_OUTPUT ;;
            "prod-eu") echo "role=arn:aws:iam::222222222222:role/GitHubActionsRole" >> $GITHUB_OUTPUT ;;
            "dev-main") echo "role=arn:aws:iam::333333333333:role/GitHubActionsRole" >> $GITHUB_OUTPUT ;;
            "dev-sandbox") echo "role=arn:aws:iam::444444444444:role/GitHubActionsRole" >> $GITHUB_OUTPUT ;;
            "staging-main") echo "role=arn:aws:iam::555555555555:role/GitHubActionsRole" >> $GITHUB_OUTPUT ;;
          esac
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ steps.account-role.outputs.role }}
          aws-region: us-east-1
          role-session-name: GitHubActions-${{ github.event.inputs.account_name }}
      
      - name: Terraform Init
        run: |
          cd accounts/${{ github.event.inputs.account_name }}
          terraform init
      
      - name: Terraform Plan
        run: |
          cd accounts/${{ github.event.inputs.account_name }}
          terraform plan -out=tfplan
        if: github.event.inputs.action == 'plan'
      
      - name: Terraform Apply
        run: |
          cd accounts/${{ github.event.inputs.account_name }}
          terraform apply -auto-approve
        if: github.event.inputs.action == 'apply'
      
      - name: Terraform Destroy
        run: |
          cd accounts/${{ github.event.inputs.account_name }}
          terraform destroy -auto-approve
        if: github.event.inputs.action == 'destroy'
```

### GitLab CI/CD Pipeline

Create `.gitlab-ci.yml`:

```yaml
stages:
  - package
  - validate
  - plan
  - deploy

variables:
  TF_VERSION: "1.5.0"
  TF_ROOT: "${CI_PROJECT_DIR}"

.terraform_template: &terraform_template
  image: 
    name: hashicorp/terraform:$TF_VERSION
    entrypoint:
      - '/usr/bin/env'
      - 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  before_script:
    - terraform --version

package_lambda:
  stage: package
  image: python:3.9
  script:
    - cd lambda
    - ./package.sh
  artifacts:
    paths:
      - lambda/ec2-shutdown-lambda.zip
    expire_in: 1 hour

.deploy_template: &deploy_template
  <<: *terraform_template
  dependencies:
    - package_lambda
  script:
    - cd accounts/$ACCOUNT_NAME
    - terraform init
    - terraform validate
    - terraform plan -out=tfplan
    - |
      if [ "$CI_COMMIT_BRANCH" = "main" ] && [ "$CI_PIPELINE_SOURCE" = "push" ]; then
        terraform apply -auto-approve tfplan
      fi
  artifacts:
    paths:
      - accounts/$ACCOUNT_NAME/tfplan
    expire_in: 1 hour

validate:
  <<: *terraform_template
  stage: validate
  dependencies:
    - package_lambda
  script:
    - make check
  only:
    - merge_requests
    - main

plan_prod_main:
  <<: *deploy_template
  stage: plan
  variables:
    ACCOUNT_NAME: "prod-main"
  environment:
    name: production/main
  only:
    - main
    - merge_requests

plan_prod_eu:
  <<: *deploy_template
  stage: plan
  variables:
    ACCOUNT_NAME: "prod-eu"
  environment:
    name: production/eu
  only:
    - main
    - merge_requests

plan_dev_main:
  <<: *deploy_template
  stage: plan
  variables:
    ACCOUNT_NAME: "dev-main"
  environment:
    name: development/main
  only:
    - main
    - merge_requests

plan_dev_sandbox:
  <<: *deploy_template
  stage: plan
  variables:
    ACCOUNT_NAME: "dev-sandbox"
  environment:
    name: development/sandbox
  only:
    - main
    - merge_requests

plan_staging_main:
  <<: *deploy_template
  stage: plan
  variables:
    ACCOUNT_NAME: "staging-main"
  environment:
    name: staging
  only:
    - main
    - merge_requests

deploy_prod_main:
  <<: *deploy_template
  stage: deploy
  variables:
    ACCOUNT_NAME: "prod-main"
  environment:
    name: production/main
  dependencies:
    - package_lambda
    - plan_prod_main
  only:
    - main
  when: manual

deploy_prod_eu:
  <<: *deploy_template
  stage: deploy
  variables:
    ACCOUNT_NAME: "prod-eu"
  environment:
    name: production/eu
  dependencies:
    - package_lambda
    - plan_prod_eu
  only:
    - main
  when: manual

deploy_dev_main:
  <<: *deploy_template
  stage: deploy
  variables:
    ACCOUNT_NAME: "dev-main"
  environment:
    name: development/main
  dependencies:
    - package_lambda
    - plan_dev_main
  only:
    - main

deploy_dev_sandbox:
  <<: *deploy_template
  stage: deploy
  variables:
    ACCOUNT_NAME: "dev-sandbox"
  environment:
    name: development/sandbox
  dependencies:
    - package_lambda
    - plan_dev_sandbox
  only:
    - main

deploy_staging_main:
  <<: *deploy_template
  stage: deploy
  variables:
    ACCOUNT_NAME: "staging-main"
  environment:
    name: staging
  dependencies:
    - package_lambda
    - plan_staging_main
  only:
    - main
```

## CI/CD Pipeline Setup

### Prerequisites for CI/CD

1. **Create IAM Roles for CI/CD**:
   
   In each target AWS account, create an IAM role for your CI/CD system:
   
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
             "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"
           }
         }
       }
     ]
   }
   ```

2. **Attach Necessary Policies**:
   - `PowerUserAccess` or custom policy with required permissions
   - S3 access for state bucket
   - IAM permissions for role management

3. **Set up Environment Variables/Secrets**:
   - AWS account IDs
   - IAM role ARNs
   - S3 bucket names

### Deployment Strategies

1. **Development Accounts**: Auto-deploy on main branch
2. **Staging Account**: Auto-deploy on main branch
3. **Production Accounts**: Manual approval required

### Branch Protection

Set up branch protection rules:
- Require PR reviews
- Require status checks (terraform validate, plan)
- Require up-to-date branches

## State Management

### S3 Backend Configuration

Each account uses its own S3 bucket for state storage:

- **Bucket naming**: `terraform-state-{ACCOUNT_ID}`
- **State key**: `ec2-shutdown/{ACCOUNT_NAME}/terraform.tfstate`
- **No DynamoDB locking**: Simplified setup as requested

### State Bucket Setup

```bash
# Create buckets with versioning and encryption
aws s3 mb s3://terraform-state-111111111111 --region us-east-1
aws s3api put-bucket-versioning --bucket terraform-state-111111111111 --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket terraform-state-111111111111 --server-side-encryption-configuration '{
  "Rules": [
    {
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }
  ]
}'
```

## Troubleshooting

### Common Issues

1. **S3 Bucket Not Found**:
   ```bash
   Error: Failed to get existing workspaces: S3 bucket does not exist
   ```
   Solution: Create the S3 bucket in the target account

2. **Permission Denied**:
   ```bash
   Error: error assuming role: AccessDenied
   ```
   Solution: Check IAM role permissions and trust relationships

3. **Lambda Package Not Found**:
   ```bash
   Error: Invalid function configuration
   ```
   Solution: Run `make package-lambda` before deployment

4. **State Lock Issues** (if using DynamoDB):
   ```bash
   Error: Error locking state
   ```
   Solution: We're not using DynamoDB locking, but if you add it later, ensure the table exists

### Debugging Commands

```bash
# Check Terraform state
terraform state list

# Show current state
terraform show

# Import existing resources (if needed)
terraform import aws_lambda_function.ec2_shutdown function_name

# Force unlock state (emergency only)
terraform force-unlock LOCK_ID

# Validate configuration
terraform validate

# Check formatting
terraform fmt -check -recursive
```

### Recovery Procedures

1. **Corrupted State**:
   - Restore from S3 version history
   - Use `terraform import` to rebuild state

2. **Failed Deployment**:
   - Check CloudWatch logs
   - Review Terraform plan output
   - Validate IAM permissions

3. **Rollback**:
   - Use Git to revert changes
   - Deploy previous version
   - Use `terraform destroy` if necessary

## Best Practices

1. **Always run `terraform plan` before `apply`**
2. **Use meaningful commit messages**
3. **Test in development accounts first**
4. **Monitor CloudWatch logs after deployment**
5. **Keep state buckets secure and versioned**
6. **Regular backup of configuration**
7. **Use descriptive tags on all resources**
8. **Implement proper IAM least-privilege access**

## Account Configuration Reference

| Account Name | Account ID | Region | Environment | S3 Bucket |
|-------------|------------|--------|-------------|-----------|
| prod-main | 111111111111 | us-east-1 | production | terraform-state-111111111111 |
| prod-eu | 222222222222 | eu-west-1 | production | terraform-state-222222222222 |
| dev-main | 333333333333 | us-east-1 | development | terraform-state-333333333333 |
| dev-sandbox | 444444444444 | us-east-1 | development | terraform-state-444444444444 |
| staging-main | 555555555555 | us-east-1 | staging | terraform-state-555555555555 |