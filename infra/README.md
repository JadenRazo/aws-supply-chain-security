# `aws-supply-chain-security` — Terraform stack

Deploys the ECR repository, EventBridge → Lambda → SNS alerting chain, and IAM into the **workloads-dev** account (`422783588447`) via the mgmt OIDC trust path.

## Resources created

| Resource | Purpose |
|---|---|
| `aws_ecr_repository.app` | ECR repo `supply-chain-demo`, IMMUTABLE tags, scan-on-push, AES-256 |
| `aws_ecr_lifecycle_policy.app` | Untagged → expire after 1d; keep last 10 tagged |
| `aws_ecr_repository_policy.app` | mgmt GitHub Actions role can push; workloads-dev can pull |
| `aws_sns_topic.scan_findings` | KMS-encrypted alert topic |
| `aws_sns_topic_subscription.email` | Email subscription to `var.notification_email` |
| `aws_lambda_function.scan_findings` | Severity-gated alert formatter |
| `aws_cloudwatch_event_rule.ecr_scan` | Routes ECR scan completion events |
| `aws_cloudwatch_log_group.scan_findings` | 7-day retention |

## Apply (locally, or via `apply.yml` workflow_dispatch)

```bash
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

Identity required: ambient creds in the **mgmt account** (`569239324174`). The `aws` provider's `assume_role` block crosses into `workloads-dev`'s `OrganizationAccountAccessRole`. CI handles this via the GitHub Actions OIDC trust set up in `sre-landing-zone/infra/07-cicd/`.

## Post-apply (REQUIRED)

`terraform apply` triggers an SNS subscription email. **Click the "Confirm subscription" link** or every alert is silently dropped.

```bash
aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)
# SubscriptionArn should NOT be "PendingConfirmation"
```

## Verify

```bash
# 1. ECR repo exists with scan-on-push
aws ecr describe-repositories --repository-names supply-chain-demo

# 2. EventBridge rule armed
aws events list-rules --name-prefix ecr-scan-supply-chain-demo

# 3. Lambda registered
aws lambda get-function --function-name scan-findings-supply-chain-demo

# 4. End-to-end test — push an image, wait ~30s, check Lambda logs
aws logs tail /aws/lambda/scan-findings-supply-chain-demo --since 5m
```

## Teardown

```bash
terraform destroy
```

`force_delete = true` on the ECR repo means images and the cosign signatures will be deleted with the repo. Sigstore Rekor entries for those signatures persist in the public log — that's by design and expected.
