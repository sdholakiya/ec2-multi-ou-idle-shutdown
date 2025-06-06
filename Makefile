.PHONY: help package-lambda init plan apply destroy validate fmt check clean

# Default target
help:
	@echo "Available targets:"
	@echo "  package-lambda     - Package the Lambda function"
	@echo "  init-<account>     - Initialize Terraform for specific account"
	@echo "  plan-<account>     - Plan Terraform changes for specific account"
	@echo "  apply-<account>    - Apply Terraform changes for specific account"
	@echo "  destroy-<account>  - Destroy resources for specific account"
	@echo "  validate-<account> - Validate Terraform configuration for specific account"
	@echo "  fmt                - Format all Terraform files"
	@echo "  check              - Check all account configurations"
	@echo "  clean              - Clean up temporary files"
	@echo ""
	@echo "Available accounts:"
	@echo "  prod-main, prod-eu, dev-main, dev-sandbox, staging-main"
	@echo ""
	@echo "Examples:"
	@echo "  make package-lambda"
	@echo "  make init-prod-main"
	@echo "  make plan-prod-main"
	@echo "  make apply-prod-main"

# Package Lambda function
package-lambda:
	@echo "Packaging Lambda function..."
	cd lambda && ./package.sh

# Initialize Terraform for specific accounts
init-prod-main:
	cd accounts/prod-main && terraform init

init-prod-eu:
	cd accounts/prod-eu && terraform init

init-dev-main:
	cd accounts/dev-main && terraform init

init-dev-sandbox:
	cd accounts/dev-sandbox && terraform init

init-staging-main:
	cd accounts/staging-main && terraform init

# Plan Terraform changes for specific accounts
plan-prod-main: package-lambda
	cd accounts/prod-main && terraform plan

plan-prod-eu: package-lambda
	cd accounts/prod-eu && terraform plan

plan-dev-main: package-lambda
	cd accounts/dev-main && terraform plan

plan-dev-sandbox: package-lambda
	cd accounts/dev-sandbox && terraform plan

plan-staging-main: package-lambda
	cd accounts/staging-main && terraform plan

# Apply Terraform changes for specific accounts
apply-prod-main: package-lambda
	cd accounts/prod-main && terraform apply

apply-prod-eu: package-lambda
	cd accounts/prod-eu && terraform apply

apply-dev-main: package-lambda
	cd accounts/dev-main && terraform apply

apply-dev-sandbox: package-lambda
	cd accounts/dev-sandbox && terraform apply

apply-staging-main: package-lambda
	cd accounts/staging-main && terraform apply

# Destroy resources for specific accounts
destroy-prod-main:
	cd accounts/prod-main && terraform destroy

destroy-prod-eu:
	cd accounts/prod-eu && terraform destroy

destroy-dev-main:
	cd accounts/dev-main && terraform destroy

destroy-dev-sandbox:
	cd accounts/dev-sandbox && terraform destroy

destroy-staging-main:
	cd accounts/staging-main && terraform destroy

# Validate Terraform configuration for specific accounts
validate-prod-main:
	cd accounts/prod-main && terraform validate

validate-prod-eu:
	cd accounts/prod-eu && terraform validate

validate-dev-main:
	cd accounts/dev-main && terraform validate

validate-dev-sandbox:
	cd accounts/dev-sandbox && terraform validate

validate-staging-main:
	cd accounts/staging-main && terraform validate

# Format all Terraform files
fmt:
	terraform fmt -recursive accounts/

# Check all account configurations
check: validate-prod-main validate-prod-eu validate-dev-main validate-dev-sandbox validate-staging-main
	@echo "All account configurations are valid"

# Clean up temporary files
clean:
	find . -name "*.tfplan" -delete
	find . -name ".terraform.lock.hcl" -delete
	find . -type d -name ".terraform" -exec rm -rf {} +
	rm -f lambda/ec2-shutdown-lambda.zip