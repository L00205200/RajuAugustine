#!/usr/bin/env bash
#
# Deploys the three-tier stack (VPC, web tier, application tier and RDS).
# Database creation is the slowest step; allow 10 to 15 minutes.
#
# Usage:
#   ./scripts/deploy-three-tier.sh
#
# Optional overrides:
#   ENVIRONMENT=prod IAM_MODE=create ./scripts/deploy-three-tier.sh

set -euo pipefail

STACK_NAME="${STACK_NAME:-l00205200-three-tier}"
ENVIRONMENT="${ENVIRONMENT:-lab}"      # lab: minimal footprint; prod: Multi-AZ
IAM_MODE="${IAM_MODE:-learnerlab}"
REGION="${AWS_REGION:-us-east-1}"

cd "$(dirname "$0")/.."

echo ">> Deploying stack $STACK_NAME ($ENVIRONMENT) in $REGION..."
aws cloudformation deploy \
  --template-file templates/02-three-tier.yaml \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides EnvironmentName="$ENVIRONMENT" IamMode="$IAM_MODE" \
  --no-fail-on-empty-changeset

URL=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" \
  --output text)

echo ""
echo "Deployment complete. Website: $URL"
echo "Allow 2 to 3 minutes for the instances to install nginx and pass health checks."
