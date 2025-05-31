# Additional Terraform configuration file for better organization

# Add this variable to variables.tf if needed
variable "is_automation_account" {
  description = "Whether this is the automation account (for IAM setup)"
  type        = bool
  default     = false
}