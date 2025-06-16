variable "target_account_id" {
  description = "AWS Account ID where resources will be deployed"
  type        = string
}

variable "target_region" {
  description = "AWS Region where resources will be deployed"
  type        = string
}

variable "cross_account_role_name" {
  description = "Name of the cross-account role to assume"
  type        = string
  default     = "EC2ShutdownRole"
}

variable "lambda_package_path" {
  description = "Path to the Lambda deployment package"
  type        = string
}

variable "environment" {
  description = "Environment name (production, development, staging)"
  type        = string
  default     = "production"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for Lambda execution"
  type        = string
  default     = "cron(0 10 * * ? *)"  # Daily at 10:00 AM UTC
}

variable "log_level" {
  description = "Log level for Lambda function"
  type        = string
  default     = "INFO"
}

variable "dry_run" {
  description = "Enable dry run mode (no actual shutdowns)"
  type        = string
  default     = "false"
}

variable "is_automation_account" {
  description = "Whether this account serves as the automation account"
  type        = bool
  default     = false
}