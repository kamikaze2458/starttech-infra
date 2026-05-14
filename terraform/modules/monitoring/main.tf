variable "environment" {}
variable "alarm_email" {}
variable "alb_arn_suffix" {}
variable "asg_name" {}

# ── CloudWatch Log Groups ─────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/much-to-do/${var.environment}/app"
  retention_in_days = 30
  tags              = { Name = "much-to-do-app-logs-${var.environment}" }
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/much-to-do/${var.environment}/system"
  retention_in_days = 14
}

# ── SNS Topic for alarm emails ────────────────────
resource "aws_sns_topic" "alarms" {
  name = "much-to-do-alarms-${var.environment}"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ── CloudWatch Alarms ─────────────────────────────
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "much-to-do-high-cpu-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Backend CPU > 80% for 4 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = var.asg_name }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "much-to-do-alb-5xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 HTTP 5xx errors per minute"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "much-to-do-alb-p99-latency-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2
  alarm_description   = "ALB p99 latency > 2 s"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
}

# ── IAM Role for EC2 → CloudWatch / ECR / SecretsManager ─
resource "aws_iam_role" "ec2" {
  name = "much-to-do-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_permissions" {
  name = "much-to-do-ec2-permissions-${var.environment}"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:*:secret:much-to-do/*"
      },
      {
        Sid    = "SSMParams"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/much-to-do/${var.environment}/*"
      }
    ]
  })
}

# Managed policy for CloudWatch agent
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "much-to-do-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2.name
}

output "app_log_group_name"         { value = aws_cloudwatch_log_group.app.name }
output "ec2_instance_profile_name"  { value = aws_iam_instance_profile.ec2.name }
output "sns_alarm_topic_arn"        { value = aws_sns_topic.alarms.arn }
