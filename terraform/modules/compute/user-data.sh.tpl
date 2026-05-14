#!/bin/bash
set -euo pipefail

yum update -y
yum install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CW_CONFIG
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/much-to-do/app.log",
            "log_group_name": "${log_group}",
            "log_stream_name": "app",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["disk_used_percent"], "resources": ["/"] }
    }
  }
}
CW_CONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

aws ecr get-login-password --region ${region} \
  | docker login --username AWS --password-stdin \
    "$(echo '${ecr_url}' | cut -d/ -f1)"

MONGO_URI=$(aws secretsmanager get-secret-value \
  --region ${region} \
  --secret-id "${mongo_secret_id}" \
  --query SecretString \
  --output text)

mkdir -p /var/log/much-to-do

docker pull ${ecr_url}:latest

docker run -d \
  --name much-to-do-backend \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /var/log/much-to-do:/var/log/much-to-do \
  -e PORT=8080 \
  -e ENVIRONMENT=${environment} \
  -e MONGO_URI="$MONGO_URI" \
  -e LOG_GROUP="${log_group}" \
  ${ecr_url}:latest

echo "much-to-do backend started"
