#!/usr/bin/env bash
#
# Deploys the static website in three steps:
#   1. Creates or updates the CloudFormation stack (S3 bucket and CloudFront).
#   2. Uploads the contents of website/ to the bucket.
#   3. Invalidates the CloudFront cache so changes are visible immediately.
#
# Usage:
#   ./scripts/deploy-website.sh
#
# Optional overrides:
#   STACK_NAME=my-stack IAM_MODE=create ./scripts/deploy-website.sh

set -euo pipefail   # Exit on the first error, unset variable or failed pipe

STACK_NAME="${STACK_NAME:-l00205200-website}"
IAM_MODE="${IAM_MODE:-learnerlab}"     # Use "create" in a standard AWS account
REGION="${AWS_REGION:-us-east-1}"

# Run from the repository root regardless of where the script is called from
cd "$(dirname "$0")/.."

# Returns a single output value from the stack
get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

echo ">> Deploying stack $STACK_NAME in $REGION (the first deployment takes about 5 minutes)..."
aws cloudformation deploy \
  --template-file templates/01-static-website.yaml \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides IamMode="$IAM_MODE" \
  --no-fail-on-empty-changeset

BUCKET=$(get_output BucketName)
DIST_ID=$(get_output DistributionId)
URL=$(get_output WebsiteURL)

echo ">> Uploading website/ to s3://$BUCKET..."
aws s3 sync website/ "s3://$BUCKET" --delete --region "$REGION"

echo ">> Invalidating the CloudFront cache..."
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" --paths "/*" \
  --query "Invalidation.Id" --output text

echo ""
echo "Deployment complete. Website: $URL"
