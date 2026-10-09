# Working on AWS Supply Chain Security

Demonstrate inspectable container inventory, scanning, signing and verification,
with a separate ECR scan-alert path. The May build screenshots and transcripts
are historical evidence, not proof that this lab is currently deployed.

Read `README.md` for scope, `.github/workflows/supply-chain.yml` for the executable
trust contract, and `docs/cosign-keyless-signing.md` for its rationale. Use
`infra/README.md`, provider/data declarations and the owning landing-zone account
map for infrastructure; use `infra/lambda/scan_findings_handler.py` and its tests
for severity/notification behavior. `docs/ci-failure-review-2026-08.md` explains
the workflow repair history; `SECURITY.md` owns private vulnerability reporting.

## Preserve the contracts

- PR/main CI in `.github/workflows/plan.yml` is credential-free static validation
  and Lambda unit tests. The apply and supply-chain workflows remain manual-only.
  Preserve typed target confirmation, the `aws-workloads-dev` environment, immutable Actions
  and scoped OIDC role chaining. An environment declaration alone does not prove
  that required reviewers are configured. A documentation fix authorizes none
  of these cloud actions.
- Require the full source commit SHA from `sre-reference-app`; keep the source
  identity, image digest and run mode traceable. The workflow builds, inventories
  and scans locally, pushes, then signs and verifies the pushed digest. Do not
  describe this as preventing every unsigned image from entering ECR.
- Gate mode fails on HIGH+ findings with available fixes (`only-fixed: true`).
  Demo mode relaxes the scan gate only; signing and verification still fail on
  error. Do not silently turn a demo result into production acceptance.
- Verification must bind the digest to the expected repository/workflow identity
  pattern and GitHub OIDC issuer. Preserve those checks; missing signatures,
  wrong digests, wrong identities or issuers must fail. A signature is not proof
  of vulnerability absence or approval to deploy. Do not claim branch-specific
  trust when the configured identity regexp allows multiple refs.
- Lambda tests mock `_publish`; they must not send SNS notifications. The script
  under `screenshots/` invokes a live notification path and is not a unit test.
  Preserve severity rejection and below-threshold behavior.
- Confirm account, region, state owner, current resources and cost before any
  authorized apply/destroy or image push. ECR `force_delete` removes images and
  signatures; preserve required evidence first. Rekor evidence has a separate
  public lifecycle. Keep secrets/state/plans private. Historical low-volume
  estimates and landing-zone compute auto-stop do not guarantee zero storage or
  service charges here.

## Validation and delivery

Run the relevant existing checks with dependencies available:

```sh
python -m unittest discover -s infra/lambda/tests -v
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
```

Backendless initialization can download providers. Signature-path changes need
positive and negative fixtures for the actual verification command; do not
substitute a successful Lambda test or a historical screenshot. There is no
committed local signature-fixture suite: report that gap and prepare isolated
checks when changing that behavior, without dispatching a paid workflow as setup.
Prose-only edits need claim/link review; they do not need cloud reproduction.

Write docs and PRs around the concrete problem, resulting behavior, actual checks
and remaining limits. Link evidence, keep one idea per paragraph and avoid broad
security guarantees. Follow repository commit conventions, otherwise use
`type: concrete change` (preferably under 72 characters). Report local changes,
push/PR effects and any separately authorized cloud execution distinctly.
