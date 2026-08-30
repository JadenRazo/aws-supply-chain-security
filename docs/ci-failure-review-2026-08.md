# CI failure review — August 2026

## Summary

Pull-request validation had been red since May even when changes were unrelated
to infrastructure. The workflow called a live AWS OIDC role and then ran a
stateful Terraform plan. By August, that role no longer resolved, so every PR
failed before reviewers received useful feedback. Terraform itself had also
drifted below the repository's `required_version` constraint.

No production incident occurred and no cloud resources were changed during this
repair. The failure was in the evidence path: a red check could no longer
distinguish a bad patch from unavailable external infrastructure.

## Contributing design errors

1. A pull-request check depended on a specific AWS account, role trust policy,
   backend, and current state.
2. The workflow's Terraform version was maintained separately from the
   configuration constraint.
3. Terraform plan text was interpolated into a JavaScript template literal in
   `github-script`, treating externally influenced output as program source.
4. The build/sign workflow ran on a push that changed its own workflow file,
   even though it could push images and publish signatures.
5. The source application defaulted to the moving `main` branch.

## Corrective controls

- PR and default-branch CI now runs only `fmt`, `init -backend=false`,
  `validate`, and deterministic Lambda unit tests. It requests no OIDC token and
  has only `contents: read` permission.
- Terraform 1.15.8 and every third-party Action are pinned explicitly; Action
  comments retain their human-readable versions.
- Apply/destroy and build/scan/sign/push are manual workflows with GitHub
  Environments. Apply requires the typed target account confirmation.
- The supply-chain workflow requires a full source commit SHA and uses its first
  12 characters as the immutable ECR tag.
- Cross-account role chaining is handled by the maintained AWS credentials
  Action rather than copying temporary credentials through `GITHUB_ENV`.

## Verification contract

A repair PR is acceptable only when both `terraform-static` and `lambda-tests`
pass. Cloud workflows are intentionally not invoked as part of PR verification;
their next authorized manual run must verify the target identity before any
write and preserve its signed-image/SBOM evidence in the run summary.
