terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  # Remote state – bootstrap bucket + table before first apply (see README)
 backend "s3" {
    bucket         = "much-to-do-terraform-state-504260085124"
    key            = "infra/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "much-to-do-tf-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "MuchToDo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repo        = "starttech-infra"
    }
  }
}

# ── Networking ────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── Storage (S3 + CloudFront) ─────────────────────
module "storage" {
  source = "./modules/storage"

  environment            = var.environment
  frontend_bucket_name   = var.frontend_bucket_name
  cloudfront_price_class = var.cloudfront_price_class
}

# ── Monitoring (CloudWatch, IAM, SNS) ─────────────
module "monitoring" {
  source = "./modules/monitoring"

  environment   = var.environment
  alarm_email   = var.alarm_email
  # These are passed in after compute creates them
  alb_arn_suffix = module.compute.alb_arn_suffix
  asg_name       = module.compute.asg_name
}

# ── Compute (ALB, ASG, ECR, ElastiCache) ──────────
module "compute" {
  source = "./modules/compute"

  environment              = var.environment
  vpc_id                   = module.networking.vpc_id
  public_subnet_ids        = module.networking.public_subnet_ids
  private_subnet_ids       = module.networking.private_subnet_ids
  instance_type            = var.instance_type
  ami_id                   = var.ami_id
  key_name                 = var.key_name
  asg_min_size             = var.asg_min_size
  asg_max_size             = var.asg_max_size
  asg_desired_capacity     = var.asg_desired_capacity
  mongo_uri_secret_id      = var.mongo_uri_secret_id
  ec2_instance_profile     = module.monitoring.ec2_instance_profile_name
  app_log_group_name       = module.monitoring.app_log_group_name
}
