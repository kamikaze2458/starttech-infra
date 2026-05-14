#!/usr/bin/env bash
# scripts/deploy-infrastructure.sh
# Manual deploy wrapper for the Terraform infra. Mainly used for bootstrapping.
# Usage: ./scripts/deploy-infrastructure.sh [environment]
set -euo pipefail

ENVIRONMENT="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

echo "==> Deploying much-to-do infrastructure — environment: $ENVIRONMENT"

command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform not found"; exit 1; }
command -v aws       >/dev/null 2>&1 || { echo "ERROR: aws-cli not found";   exit 1; }

aws sts get-caller-identity --query Account --output text >/dev/null \
  || { echo "ERROR: AWS credentials not configured"; exit 1; }

cd "$TF_DIR"

echo "==> terraform init"
terraform init -upgrade

echo "==> terraform validate"
terraform validate

echo "==> terraform plan"
terraform plan \
  -var="environment=$ENVIRONMENT" \
  -var-file="terraform.tfvars" \
  -out="tfplan-$ENVIRONMENT"

if [[ "${CI:-false}" == "true" ]]; then
  terraform apply -auto-approve "tfplan-$ENVIRONMENT"
else
  read -r -p "Apply the plan? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  terraform apply "tfplan-$ENVIRONMENT"
fi

echo ""
echo "==> Deployment complete. Outputs:"
terraform output
