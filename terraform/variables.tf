variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev | staging | prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

# ── Networking ────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# ── Storage ───────────────────────────────────────
variable "frontend_bucket_name" {
  description = "Globally unique S3 bucket name for React frontend assets"
  type        = string
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

# ── Compute ───────────────────────────────────────
variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID for your region"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "mongo_uri_secret_id" {
  description = "AWS Secrets Manager secret ID (name or ARN) for the MongoDB Atlas URI"
  type        = string
}

# ── Monitoring ────────────────────────────────────
variable "alarm_email" {
  description = "Email for CloudWatch SNS alarm notifications"
  type        = string
}
