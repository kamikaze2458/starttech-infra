output "vpc_id" {
  value = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "Paste this as REACT_APP_API_URL in frontend pipeline"
  value       = module.compute.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "Frontend URL (add CNAME for custom domain)"
  value       = module.storage.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "Set as CLOUDFRONT_DISTRIBUTION_ID GitHub secret"
  value       = module.storage.cloudfront_distribution_id
}

output "s3_frontend_bucket" {
  description = "Set as FRONTEND_S3_BUCKET GitHub secret"
  value       = module.storage.frontend_bucket_name
}

output "ecr_repository_url" {
  description = "Set as ECR_REPO_URL GitHub secret"
  value       = module.compute.ecr_repository_url
}

output "elasticache_redis_endpoint" {
  description = "Set as REDIS_ADDR env var in backend container"
  value       = module.compute.elasticache_endpoint
}

output "launch_template_id" {
  description = "Set as LAUNCH_TEMPLATE_ID GitHub secret for pipeline"
  value       = module.compute.launch_template_id
}

output "asg_name" {
  description = "Set as ASG_NAME GitHub secret"
  value       = module.compute.asg_name
}

output "cloudwatch_log_group" {
  value = module.monitoring.app_log_group_name
}
