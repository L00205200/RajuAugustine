#!/usr/bin/env bash
#
# Deletes both stacks so that no resources are left running.
# The website bucket is emptied automatically by the cleanup Lambda function.
# The database retains a final snapshot (DeletionPolicy: Snapshot).

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

for STACK in l00205200-three-tier l00205200-website; do
  echo ">> Deleting $STACK..."
  aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION"
done

echo ">> Waiting for deletion to complete (CloudFront can take around 10 minutes)..."
aws cloudformation wait stack-delete-complete --stack-name l00205200-three-tier --region "$REGION"
aws cloudformation wait stack-delete-complete --stack-name l00205200-website --region "$REGION"

echo "All stacks deleted."
echo "Optional: delete the remaining RDS snapshot in the console (RDS > Snapshots)."
