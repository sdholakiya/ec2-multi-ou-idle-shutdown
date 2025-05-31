terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    # Backend configuration will be provided via -backend-config in CI/CD
  }
}

provider "aws" {
  region = var.target_region
  
  assume_role {
    role_arn     = "arn:aws:iam::${var.target_account_id}:role/${var.cross_account_role_name}"
    session_name = "terraform-ec2-shutdown"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "ec2_shutdown_logs" {
  name              = "/aws/lambda/ec2-auto-shutdown"
  retention_in_days = 30
  
  tags = {
    Environment = var.environment
    Purpose     = "EC2AutoShutdown"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "ec2-shutdown-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Purpose     = "EC2AutoShutdown"
  }
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "ec2-shutdown-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.target_region}:${var.target_account_id}:log-group:/aws/lambda/ec2-auto-shutdown:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StopInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "ec2_shutdown" {
  filename         = var.lambda_package_path
  function_name    = "ec2-auto-shutdown"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "ec2_shutdown.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  source_code_hash = filebase64sha256(var.lambda_package_path)

  environment {
    variables = {
      LOG_LEVEL = var.log_level
      DRY_RUN   = var.dry_run
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.ec2_shutdown_logs
  ]

  tags = {
    Environment = var.environment
    Purpose     = "EC2AutoShutdown"
  }
}

# EventBridge Rule for scheduled execution
resource "aws_cloudwatch_event_rule" "ec2_shutdown_schedule" {
  name                = "ec2-shutdown-schedule"
  description         = "Trigger EC2 shutdown Lambda daily"
  schedule_expression = var.schedule_expression

  tags = {
    Environment = var.environment
    Purpose     = "EC2AutoShutdown"
  }
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.ec2_shutdown_schedule.name
  target_id = "EC2ShutdownLambdaTarget"
  arn       = aws_lambda_function.ec2_shutdown.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_shutdown.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_shutdown_schedule.arn
}