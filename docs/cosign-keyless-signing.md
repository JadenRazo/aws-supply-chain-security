# Cosign keyless signing — how this pipeline avoids managing a signing key

Traditional image signing burns time on key management: generate keypair, store private key in a secrets manager, rotate periodically, recover when someone leaks it, audit who used it. Sigstore's **keyless** flow replaces all of that with two short-lived primitives — an OIDC token and an X.509 certificate — and a public transparency log.

## The flow this workflow uses

```
GitHub Actions (run id 12345)
    │
    │ 1. id-token: write — request OIDC token from GitHub
    ▼
GitHub OIDC issuer  (token.actions.githubusercontent.com)
    │
    │ 2. cosign sign --yes <image>
    │    sends OIDC token to Sigstore Fulcio
    ▼
Sigstore Fulcio  (CA)
    │
    │ 3. validates the OIDC claims
    │    issues a short-lived (~10 min) X.509 cert binding
    │    those claims to a freshly generated keypair
    ▼
cosign  (in the runner)
    │
    │ 4. signs the image digest with the keypair's private key
    │    deletes the private key (it was ephemeral, on-disk only briefly)
    │
    │ 5. uploads {signature, certificate, OIDC claims} to Rekor
    ▼
Sigstore Rekor  (transparency log)
    │
    │ 6. appends an entry to a Merkle-tree-backed log
    │    returns inclusion proof
    ▼
ECR
    │
    │ 7. cosign pushes the signature as a sibling artifact:
    │    sha256-<image_digest>.sig — same repo, separate tag
    ▼
verifier  (anywhere)
    │
    │ 8. cosign verify <image> --certificate-identity-regexp ...
    │    pulls signature + cert from ECR
    │    pulls Rekor entry, validates inclusion
    │    asserts cert chains to Fulcio root
    │    asserts cert's identity claims match expected pattern
```

## What's in the cert (the load-bearing assertion)

When `cosign verify` runs, it doesn't ask "do you have *a* valid signature." It asks "is the signature on this image bound to a Fulcio cert whose embedded OIDC claims match what I expect?" In this project the expected claims are:

- `iss = https://token.actions.githubusercontent.com` (only GitHub Actions issued this)
- Subject (SAN URI) matches `https://github.com/JadenRazo/aws-supply-chain-security/.github/workflows/supply-chain.yml@<ref>` — only this specific workflow file in this specific repo

A signature from any other repo, any other workflow, any other identity provider fails verification. There is no shared signing key to leak, no key rotation, no offline storage.

## Why this is better than managed PKI

| Concern | Managed PKI (e.g. KMS-backed signing key) | Keyless (Sigstore) |
|---|---|---|
| Key compromise | Long-lived secret; rotation is operationally painful | Each cert lives ~10 min; rotation is automatic |
| Audit trail | Wherever you log signing events (often inconsistent) | Public Rekor log; tamper-evident; queryable |
| Identity binding | "Some service held the key" — weak | "This specific workflow run on this commit" — strong |
| Cost | KMS key + ops overhead | $0 |

## What it doesn't solve

- **Repo compromise** — if an attacker pushes a malicious commit and triggers the workflow, the resulting signature is genuinely valid (cert claims match). Defense-in-depth here is branch protection, required reviews, and CODEOWNERS.
- **Sigstore trust root rotation** — Fulcio + Rekor have a root of trust that's expected to rotate. `cosign` handles this transparently via TUF, but air-gapped verifiers need to update their trust bundle.
- **Offline verification** — pulling Rekor entries requires network access to `rekor.sigstore.dev`. Air-gapped verification is possible with the `--offline` flag once you have a local copy of the Rekor entry, but it's not the default flow.

## Reference

- Sigstore: <https://docs.sigstore.dev/>
- Cosign keyless signing: <https://docs.sigstore.dev/cosign/signing/overview/>
- Fulcio: <https://docs.sigstore.dev/fulcio/overview/>
- Rekor: <https://docs.sigstore.dev/rekor/overview/>
- GitHub OIDC trust: <https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect>
