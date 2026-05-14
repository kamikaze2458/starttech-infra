# Much-To-Do Infrastructure (`starttech-infra`)

Terraform IaC for the Much-To-Do application platform on AWS.

## Structure

```
starttech-infra/
├── .github/workflows/
│   └── infrastructure-deploy.yml   # Validate → Plan → Apply pipeline
├── terraform/
│   ├── main.tf                     # Root module wiring
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example    # Copy → terraform.tfvars (never commit)
│   └── modules/
│       ├── networking/   # VPC, subnets, IGW, NAT gateways, routes
│       ├── compute/      # ECR, ALB, Launch Template, ASG, ElastiCache
│       ├── storage/      # S3 + CloudFront (OAC)
│       └── monitoring/   # CloudWatch log groups, alarms, SNS, IAM
├── scripts/
│   └── deploy-infrastructure.sh
└── monitoring/
    ├── cloudwatch-dashboard.json
    ├── alarm-definitions.json
    └── log-insights-queries.txt
```

## Quick Start

### 1. Bootstrap state backend (once)

```bash
aws s3api create-bucket --bucket much-to-do-terraform-state --region us-east-1
aws s3api put-bucket-versioning \
  --bucket much-to-do-terraform-state \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name much-to-do-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### 2. Store MongoDB Atlas URI

```bash
aws secretsmanager create-secret \
  --name "much-to-do/mongo-uri" \
  --secret-string '{"uri":"mongodb+srv://..."}'
```

### 3. Deploy

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Fill in all values
./scripts/deploy-infrastructure.sh prod
```

## Key Outputs

After `terraform apply`, run `terraform output` to get values needed as GitHub Secrets in the app repo:

| Output                       | GitHub Secret                    |
|------------------------------|----------------------------------|
| `alb_dns_name`               | `REACT_APP_API_URL`, `ALB_DNS_NAME` |
| `cloudfront_distribution_id` | `CLOUDFRONT_DISTRIBUTION_ID`     |
| `s3_frontend_bucket`         | `FRONTEND_S3_BUCKET`             |
| `ecr_repository_url`         | `ECR_REPO_URL`                   |
| `launch_template_id`         | `LAUNCH_TEMPLATE_ID`             |
| `asg_name`                   | `ASG_NAME`                       |
| `elasticache_redis_endpoint` | `REDIS_ADDR`                     |

## Infrastructure Pipeline

The `infrastructure-deploy.yml` workflow runs on every push to `main` that touches `terraform/`:

1. **Validate** — `terraform fmt`, `terraform validate`, tfsec scan
2. **Plan** — creates plan artifact; posts plan summary as PR comment
3. **Apply** — requires GitHub Environment approval for `prod`; uses OIDC (no static AWS keys)

## Required GitHub Secrets (infra repo)

| Secret                  | Description                          |
|-------------------------|--------------------------------------|
| `AWS_OIDC_ROLE_ARN`     | GitHub Actions IAM role              |
| `FRONTEND_BUCKET_NAME`  | Desired S3 bucket name               |
| `EC2_AMI_ID`            | Amazon Linux 2023 AMI for your region|
| `EC2_KEY_NAME`          | EC2 key pair name                    |
| `MONGO_URI_SECRET_ID`   | Secret Manager ID for MongoDB URI    |
| `ALARM_EMAIL`           | SNS email for CloudWatch alarms      |
