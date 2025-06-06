terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "terraform-state-111111111111"
    key    = "ec2-shutdown/prod-main/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.target_region
  
  assume_role {
    role_arn     = "arn:aws:iam::${var.target_account_id}:role/${var.cross_account_role_name}"
    session_name = "terraform-ec2-shutdown"
  }
}