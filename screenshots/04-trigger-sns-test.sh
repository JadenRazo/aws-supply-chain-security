#!/bin/bash
# Trigger the alerting path end-to-end without waiting for an actual vulnerable image.
#
# What this does:
#   1. Confirms ambient creds are mgmt; chains into workloads-dev
#   2. Confirms the SNS subscription has been activated (otherwise the email is silently dropped)
#   3. Synchronously invokes the scan-findings Lambda with a synthetic ECR scan event
#      whose finding-severity-counts.HIGH=5, CRITICAL=2
#   4. The Lambda's severity gate trips, it publishes to SNS, you get the email
#
# Use AFTER terraform apply has run AND you've clicked "Confirm subscription" in the
# SNS confirmation email sent to the address in var.notification_email.

set -euo pipefail

WORKLOADS_DEV_ACCOUNT_ID="422783588447"
REGION="us-west-2"
LAMBDA_NAME="scan-findings-supply-chain-demo"
SNS_TOPIC_ARN="arn:aws:sns:${REGION}:${WORKLOADS_DEV_ACCOUNT_ID}:ecr-scan-findings-supply-chain-demo"
PAYLOAD_FILE="$(dirname "$0")/04-sns-test-payload.json"

echo "Step 1: chain into workloads-dev"
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${WORKLOADS_DEV_ACCOUNT_ID}:role/OrganizationAccountAccessRole" \
  --role-session-name "sns-test-$(date +%s)" \
  --output json)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .Credentials.SessionToken)
aws sts get-caller-identity

echo ""
echo "Step 2: check SNS subscription state"
SUB_STATUS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --region "$REGION" \
  --query 'Subscriptions[?Protocol==`email`].SubscriptionArn' --output text)
if [ "$SUB_STATUS" = "PendingConfirmation" ]; then
  echo "  SNS subscription is still PendingConfirmation — click 'Confirm subscription'"
  echo "  in the email AWS sent before re-running this script. Otherwise the email"
  echo "  will be silently dropped."
  exit 1
fi
echo "  Subscription active: $SUB_STATUS"

echo ""
echo "Step 3: invoke Lambda with synthetic HIGH+ event"
aws lambda invoke \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" \
  --cli-binary-format raw-in-base64-out \
  --payload "file://${PAYLOAD_FILE}" \
  /tmp/lambda-response.json

echo ""
echo "Lambda response:"
cat /tmp/lambda-response.json
echo ""

echo ""
echo "Step 4: check email at the address in var.notification_email."
echo "Subject line: '[ECR scan] supply-chain-demo :: 2 crit / 5 high'"
echo ""
echo "Tail Lambda logs to verify it published:"
echo "  aws logs tail /aws/lambda/${LAMBDA_NAME} --since 1m --region ${REGION}"
