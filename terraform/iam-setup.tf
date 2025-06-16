# This file contains the IAM resources needed for cross-account access
# Deploy this in your central automation account first

# IAM Role in Automation Account (deploy this first)
resource "aws_iam_role" "automation_role" {
  count = var.is_automation_account ? 1 : 0
  name  = "EC2ShutdownAutomationRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${var.target_account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "automation_policy" {
  count = var.is_automation_account ? 1 : 0
  name  = "EC2ShutdownAutomationPolicy"
  role  = aws_iam_role.automation_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/EC2ShutdownRole"
        ]
      }
    ]
  })
}

# Additional policy for automation account to perform EC2 operations directly (if needed)
resource "aws_iam_role_policy" "automation_ec2_policy" {
  count = var.is_automation_account ? 1 : 0
  name  = "EC2ShutdownDirectPolicy"
  role  = aws_iam_role.automation_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2IdleShutdownPermissions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus", 
          "ec2:DescribeTags",
          "ec2:StopInstances",
          "ec2:MonitorInstances",
          "ec2:UnmonitorInstances"
        ]
        Resource = "*"
        Condition = {
          "ForAllValues:StringEquals" = {
            "ec2:InstanceState" = ["running"]
          }
        }
      },
      {
        Sid    = "CloudWatchMetricsAccess"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AWS/EC2"
          }
        }
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream", 
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:*:${var.target_account_id}:log-group:/aws/lambda/ec2-auto-shutdown*",
          "arn:aws:logs:*:${var.target_account_id}:log-group:/aws/lambda/ec2-auto-shutdown*:*"
        ]
      },
      {
        Sid    = "LambdaExecutionPermissions"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:*:${var.target_account_id}:function:ec2-auto-shutdown"
      },
      {
        Sid    = "EventBridgePermissions"
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "events:DescribeRule",
          "events:ListTargetsByRule"
        ]
        Resource = [
          "arn:aws:events:*:${var.target_account_id}:rule/ec2-shutdown-schedule",
          "arn:aws:events:*:${var.target_account_id}:event-bus/default"
        ]
      }
    ]
  })
}

# Cross-Account Role Template (deploy this in each target account)
# This is a template - you'll need to customize the trust policy for your org

locals {
  automation_account_id = "YOUR_AUTOMATION_ACCOUNT_ID"  # Replace with your automation account ID
}

resource "aws_iam_role" "cross_account_role" {
  count = var.is_automation_account ? 0 : 1
  name  = var.cross_account_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.automation_account_id}:role/EC2ShutdownAutomationRole"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "ec2-shutdown-${var.target_account_id}"
          }
        }
      }
    ]
  })

  tags = {
    Purpose = "EC2AutoShutdown"
  }
}

resource "aws_iam_role_policy" "cross_account_policy" {
  count = var.is_automation_account ? 0 : 1
  name  = "EC2ShutdownCrossAccountPolicy"
  role  = aws_iam_role.cross_account_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:*:${var.target_account_id}:function:ec2-auto-shutdown"
      }
    ]
  })
}