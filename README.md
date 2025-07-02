# EC2 Auto-Shutdown Solution

Automated EC2 instance shutdown based on CPU utilization across AWS Organizations with GitLab CI/CD integration.

## Features

- **Cross-Account Deployment**: Works across multiple AWS accounts in your organization
- **Smart Shutdown Logic**: Shuts down instances idle for 3+ hours (configurable)
- **Instance Protection**: Excludes P/G instance types and instances tagged `Shutdown=No`
- **Secure Credentials**: No AWS credentials stored in GitLab
- **Environment Management**: Separate deployments for production, development, staging
- **Comprehensive Logging**: Full audit trail of all actions

## Repository Structure

```
ec2-auto-shutdown/
├── .gitlab-ci.yml              # GitLab CI/CD pipeline
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Main Terraform configuration
│   ├── variables.tf            # Variable definitions
│   ├── outputs.tf              # Output definitions
│   └── iam-setup.tf            # IAM roles for cross-account access
├── lambda/                     # Lambda function code
│   ├── src/
│   │   └── ec2_shutdown.py     # Main Lambda function
│   ├── requirements.txt        # Python dependencies
│   └── package.sh              # Packaging script
├── config/
│   └── ou-accounts.yaml        # Account and OU configuration
├── scripts/
│   └── deploy.sh               # Deployment helper script
└── README.md                   # This file
```

## Quick Start

### 1. Configure Your Accounts

Edit `config/ou-accounts.yaml` with your AWS account details:

```yaml
organizational_units:
  - name: "production"
    accounts:
      - account_id: "YOUR_PROD_ACCOUNT_ID"
        role_name: "EC2ShutdownRole"
        regions: ["us-east-1", "us-west-2"]
```

### 2. Set Up IAM Roles

#### Understanding Automation vs Target Accounts

- **Automation Account**: The central account that runs the Lambda function and orchestrates EC2 shutdowns across all other accounts. Choose one account (typically your main/central account) as the automation account.
- **Target Accounts**: All accounts (including the automation account itself) where EC2 instances will be evaluated and potentially shut down.

#### Setup Process

The script automatically detects whether to create an automation account role or a cross-account role by comparing your current AWS account with the target account ID from the configuration.

**Step 1: Set up the Automation Account**
```bash
# Authenticate to your chosen automation account (e.g., prod-main)
# Run this command to create the automation role:
./scripts/deploy.sh setup-iam --account-name prod-main
```

**Step 2: Set up Target Accounts (Cross-Account Roles)**
```bash
# Authenticate to each target account and create cross-account roles
# For other accounts:
./scripts/deploy.sh setup-iam --account-name prod-eu
./scripts/deploy.sh setup-iam --account-name dev-main
./scripts/deploy.sh setup-iam --account-name dev-sandbox
./scripts/deploy.sh setup-iam --account-name staging-main
```

**Available account names:** `prod-main`, `prod-eu`, `dev-main`, `dev-sandbox`, `staging-main`

**How it works:**
- Script parses `config/ou-accounts.yaml` to map account names to account IDs
- **Same account** (automation account): Creates `EC2ShutdownAutomationRole` with cross-account assumption and direct EC2 operation permissions
- **Different account** (target account): Creates `EC2ShutdownRole` with EC2 shutdown permissions and trust relationship to automation account

**Roles Created:**
- **Automation Account**: `EC2ShutdownAutomationRole` + `EC2ShutdownDirectPolicy` (comprehensive permissions for orchestration)
- **Target Accounts**: `EC2ShutdownRole` (scoped EC2 and CloudWatch permissions, trusted by automation account)

### 3. Configure GitLab Variables

Set these variables in your GitLab project:
- `AUTOMATION_ROLE_ARN`: ARN of the automation account role
- `AWS_REGION`: Default AWS region

### 4. Deploy

Push to your configured branches to trigger deployments:
- `main` branch → production
- `develop` branch → development  
- `staging` branch → staging

## Shutdown Logic

An EC2 instance will be shut down if **ALL** conditions are met:

✅ **CPU Utilization**: ALL datapoints CPU < 1% for 3+ hours  
✅ **Instance Type**: NOT P or G type (excludes GPU/ML instances)  
✅ **Tag Check**: Does NOT have `Shutdown=No` tag  

### Instance Protection

To protect an instance from shutdown, add this tag:
```
Key: Shutdown
Value: No
```

## Configuration

### Global Settings

Edit `config/ou-accounts.yaml` to customize:

```yaml
global_settings:
  schedule_expression: "cron(0 10 * * ? *)"  # Daily at 10:00 AM UTC
  cpu_threshold: 1.0                         # CPU percentage threshold
  idle_duration_hours: 3                     # Hours of idle time
  dry_run: false                            # Test mode
```

### Environment-Specific Deployment

The solution supports three environments:
- **Production**: Deployed from `main` branch
- **Development**: Deployed from `develop` branch  
- **Staging**: Deployed from `staging` branch

## Manual Operations

### Package Lambda Function
```bash
./scripts/deploy.sh package-lambda
```

### Validate Configuration
```bash
./scripts/deploy.sh validate
```

### Deploy to Specific Account
```bash
./scripts/deploy.sh deploy --environment production --account-id 123456789012 --region us-east-1
```

### Test Lambda Locally
```bash
./scripts/deploy.sh test-lambda
```

### Enable Dry Run Mode
```bash
./scripts/deploy.sh deploy --environment development --dry-run
```

## Monitoring

### CloudWatch Logs

Lambda execution logs are available at:
```
/aws/lambda/ec2-auto-shutdown
```

### Log Format

Each execution logs:
- Total instances evaluated
- Instances skipped (with reasons)
- Instances shut down
- Detailed reasoning for each decision

### Sample Log Output

```json
{
  "message": "EC2 auto-shutdown completed successfully",
  "total_instances_evaluated": 15,
  "instances_skipped": 8,
  "instances_shutdown": 2,
  "dry_run": false,
  "skipped_instances": [
    {
      "instance_id": "i-1234567890abcdef0",
      "instance_type": "p3.2xlarge",
      "reason": "Instance type p3.2xlarge is excluded (P/G type)"
    }
  ],
  "shutdown_results": [
    {
      "instance_id": "i-0987654321fedcba0",
      "instance_type": "t3.medium",
      "action": "shutdown",
      "status": "success"
    }
  ]
}
```

## Security

### Cross-Account Access

- Uses IAM roles with least-privilege permissions
- No long-term credentials stored anywhere
- Cross-account access via STS AssumeRole
- GitLab integration via OIDC (no stored AWS keys)

### Permissions Required

**Automation Account Role** (`EC2ShutdownAutomationRole`):
- Cross-account role assumption: `sts:AssumeRole`
- Direct EC2 operations (if needed): `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus`, `ec2:StopInstances`, `ec2:DescribeTags`
- CloudWatch metrics: `cloudwatch:GetMetricStatistics`, `cloudwatch:GetMetricData` 
- Lambda execution: `lambda:InvokeFunction`
- EventBridge: `events:PutEvents`, `events:DescribeRule`
- CloudWatch Logs: `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

**Target Account Cross-Account Role** (`EC2ShutdownRole`):
- `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus`, `ec2:StopInstances`, `ec2:DescribeTags`
- `cloudwatch:GetMetricStatistics`, `cloudwatch:GetMetricData`
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`
- `lambda:InvokeFunction`

All permissions include security conditions to restrict access to running instances and EC2-related resources only.

## Troubleshooting

### Common Issues

**"No metrics found for instance"**
- Instance may be too new (< 3.5 hours old)
- CloudWatch detailed monitoring may be disabled

**"Insufficient metrics"**  
- Instance needs at least 3 hours of continuous CloudWatch data
- Check if instance was recently started
- Ensure 5-minute intervals are present without significant gaps

**"Permission denied"**
- Verify cross-account IAM role trust relationships
- Check that GitLab OIDC is properly configured

### Testing

Enable dry run mode to test without actual shutdowns:

```yaml
# In config/ou-accounts.yaml
global_settings:
  dry_run: true
```

Or use the deployment script:
```bash
./scripts/deploy.sh deploy --environment development --dry-run
```

## Cost Optimization

This solution helps reduce AWS costs by:
- Automatically shutting down idle development/test instances
- Protecting critical workloads (P/G instances, tagged instances)
- Providing detailed logging for cost analysis
- Running on a schedule to minimize operational overhead

## Support

For issues or questions:
1. Check CloudWatch logs for execution details
2. Verify IAM permissions and trust relationships  
3. Test with dry run mode enabled
4. Review instance tags and types

