variable "environment" {}
variable "vpc_id" {}
variable "public_subnet_ids"    { type = list(string) }
variable "private_subnet_ids"   { type = list(string) }
variable "instance_type" {}
variable "ami_id" {}
variable "key_name" {}
variable "asg_min_size"         { type = number }
variable "asg_max_size"         { type = number }
variable "asg_desired_capacity" { type = number }
variable "mongo_uri_secret_id" {}
variable "ec2_instance_profile" {}
variable "app_log_group_name" {}

data "aws_region" "current" {}

# ECR Repository
resource "aws_ecr_repository" "backend" {
  name                 = "much-to-do-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "much-to-do-ecr-${var.environment}" }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

# Security Group - ALB
resource "aws_security_group" "alb" {
  name        = "much-to-do-alb-sg-${var.environment}"
  description = "Internet to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "much-to-do-alb-sg-${var.environment}" }
}

# Security Group - Backend
resource "aws_security_group" "backend" {
  name        = "much-to-do-backend-sg-${var.environment}"
  description = "ALB to backend EC2"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "much-to-do-backend-sg-${var.environment}" }
}

# Security Group - Redis
resource "aws_security_group" "redis" {
  name        = "much-to-do-redis-sg-${var.environment}"
  description = "Backend to ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "much-to-do-redis-sg-${var.environment}" }
}

# Application Load Balancer
resource "aws_lb" "backend" {
  name               = "much-to-do-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  tags               = { Name = "much-to-do-alb-${var.environment}" }
}

resource "aws_lb_target_group" "backend" {
  name        = "much-to-do-tg-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = { Name = "much-to-do-tg-${var.environment}" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# Launch Template
resource "aws_launch_template" "backend" {
  name_prefix   = "much-to-do-lt-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.ec2_instance_profile
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.backend.id]
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tpl", {
    ecr_url         = aws_ecr_repository.backend.repository_url
    region          = data.aws_region.current.name
    environment     = var.environment
    log_group       = var.app_log_group_name
    mongo_secret_id = var.mongo_uri_secret_id
  }))

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "much-to-do-backend-${var.environment}"
      Environment = var.environment
    }
  }

  lifecycle { create_before_destroy = true }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "backend" {
  name                      = "much-to-do-asg-${var.environment}"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.backend.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "much-to-do-backend-${var.environment}"
    propagate_at_launch = true
  }
}

# ASG Scaling Policy
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "much-to-do-cpu-target-${var.environment}"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "much-to-do-redis-sng-${var.environment}"
  subnet_ids = var.private_subnet_ids
}

# ElastiCache Redis
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "much-to-do-redis-${var.environment}"
  description                = "Much-To-Do sessions and cache"
  node_type                  = "cache.t3.micro"
  port                       = 6379
  num_cache_clusters         = 2
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = true
  tags                       = { Name = "much-to-do-redis-${var.environment}" }
}

# Outputs
output "alb_dns_name"         { value = aws_lb.backend.dns_name }
output "alb_arn_suffix"       { value = aws_lb.backend.arn_suffix }
output "asg_name"             { value = aws_autoscaling_group.backend.name }
output "ecr_repository_url"   { value = aws_ecr_repository.backend.repository_url }
output "elasticache_endpoint" { value = aws_elasticache_replication_group.redis.primary_endpoint_address }
output "launch_template_id"   { value = aws_launch_template.backend.id }
