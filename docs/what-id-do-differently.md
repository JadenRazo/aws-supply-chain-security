# What I'd do differently in production

This project is intentionally a **portfolio cut**: small, scannable, $0/mo. The shape is right; the placement and depth would change at production scale. Below is the honest list of compromises, with what I'd swap and why.

## 1. ECR lives in `workloads-dev`. In production it should live in `audit-security`.

A central registry account is the standard pattern: one place to enforce signing, one bucket of vuln data, one set of repository policies, one cross-account replication path to regional registries. I put ECR in `workloads-dev` here because the project is a single-account demo and the cross-account replication setup would have doubled the Terraform LOC for no extra signal.

**Migration path**: lift ECR resources into a `central-registry/` module, deploy in `audit-security`, add `aws_ecr_replication_configuration` for region/account fan-out, swap the workflow's chain to terminate in audit-security for push and workloads-prod for pull.

## 2. SBOM lives as a workflow artifact. It should be a cosign **attestation** alongside the signature.

`anchore/sbom-action@v0` uploads `sbom.spdx.json` as a GitHub-side artifact with 30-day retention. That's findable but not durable, not signed, and not co-located with the image.

**The right shape**: `cosign attest --predicate sbom.spdx.json --type spdxjson <image>`. That puts the SBOM in Rekor as a signed predicate, attached to the same image digest the signature covers. Verification in the pull path becomes `cosign verify-attestation --type spdxjson` — and downstream tooling like `grype attestation:` can consume the signed SBOM directly without re-pulling the image.

I left this off the v1 because it adds another `--certificate-identity` assertion to the verify path and the screenshots get noisier. Worth adding next iteration.

## 3. The vuln scan runs once, at build. It should also run continuously against deployed images.

Grype scans the image at the moment of build. New CVEs land daily; the image that passed today's scan can fail tomorrow's. Production needs a scheduled re-scan — daily for prod images, weekly for staging — with the same severity gate and the same alerting path.

**The shape**: a separate EventBridge schedule → Lambda → `aws ecr start-image-scan` for every image in the registry's "active" tag set, with a tag selector pulling from a Parameter Store list. ECR's "Enhanced scanning" via Inspector v2 also covers continuous scanning natively, at a price ($0.09/image/scan).

## 4. Lambda decodes the EventBridge event manually. EventBridge's input transformer would be cleaner.

The Lambda code parses the raw event detail and formats a Slack/email-ready message. EventBridge supports input transformers that produce a templated string at the rule level, which would let the Lambda be a thin "publish to SNS" wrapper rather than a presentation layer.

I went with code because the transformer's templating syntax is awkward for nested objects (`finding-severity-counts.HIGH`) and I wanted the severity-threshold gate to be testable. In a larger system I'd push the formatting back into EventBridge so the Lambda is purely policy.

## 5. Notifications go to one email. Production needs a tiered routing policy.

`var.notification_email` is a single subscriber. In production:
- Severity CRITICAL → PagerDuty (page a human)
- Severity HIGH → Slack channel + email digest
- Severity MEDIUM → ticket in the security-issues queue
- Severity LOW → metrics dashboard only

The fan-out lives at the SNS layer (multiple subscriptions) and the routing logic lives in the Lambda. The current code is structured to support this — the gate is parameterized — but only the email subscription is wired up.

## 6. Terraform state is local. It should be S3 + DynamoDB.

`infra/` uses local state by default. That's fine for a single-developer project where `apply.yml` is `workflow_dispatch`-only and there's no concurrent-apply risk. In a team setting it's untenable.

**Migration path**: `_backend/` directory (matches the convention from `sre-landing-zone`) with an S3 backend bucket in `mgmt`, DynamoDB lock table, KMS-encrypted state. The module's `terraform init -migrate-state` does the rest.

## 7. ECR repo policy hardcodes the mgmt account ID. It should reference an SSM-driven account map.

`var.mgmt_account_id` defaults to the right value but bypasses the canonical lookup at `/sre-landing-zone/account-map`. The right shape is the same as `local.workloads_dev_account_id` — read once from SSM, derive everything from the map.

I left the explicit variable as an escape hatch in case the SSM param is unavailable at apply time (e.g., a fresh setup before `sre-landing-zone` is deployed). Documented escape hatches should be temporary; this one should grow up.

## 8. No SLSA provenance attestation.

`cosign sign` proves "this image was signed by a workflow whose OIDC subject matches X." It does **not** prove "this image was built from commit Y at SHA Z by command W." That's what SLSA Provenance attestations are for: a separate `cosign attest --type slsaprovenance --predicate ...` step that captures the build environment, command, materials.

GitHub's `actions/attest-build-provenance@v1` automates the bulk of this. Adding it to v2 of this project gives a `provenance.intoto.jsonl` artifact in Rekor and unlocks SLSA Level 3 verification at the consumer.

## 9. Source image is checked out at `main` by default. It should pin to a SHA.

`actions/checkout@v4` of `JadenRazo/sre-reference-app` defaults to `main`. That makes the build non-reproducible — `main` moves. Production builds should pin to a SHA, captured in the SLSA provenance, and the workflow's `inputs.source_ref` should default to a known-good SHA. I kept `main` because the project's narrative is "always sign the latest of the source app I deploy"; in real systems the latest-SHA pin lives upstream.

## 10. No retry / DLQ on the Lambda.

`aws_lambda_function.scan_findings` runs on EventBridge invocations and has the default async retry policy (2 retries, no DLQ). If SNS Publish fails three times the alert is silently dropped and there's no audit. Adding `aws_lambda_function_event_invoke_config { destination_config { on_failure { destination = sqs_dlq.arn } } }` is two lines and makes alert delivery actually durable.

---

**Summary**: this v1 demonstrates the **shape** of supply-chain hardening — sign every image, gate every push, alert on regressions. Production-grade implementations of the same shape add an attestation pipeline, central registry placement, continuous re-scanning, tiered routing, durable alerting, and remote state. The interview talk is "here's the shape, here's the explicit list of things I'd grow next, and here's why each one matters." That list is more honest than pretending the v1 is production-ready.
