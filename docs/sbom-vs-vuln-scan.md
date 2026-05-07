# SBOM vs vulnerability scan

These are not the same artifact and they don't replace each other. Skipping either gives an incomplete supply-chain picture.

## SBOM (Software Bill of Materials)

An **inventory** of what's inside an image — every package, every version, every license. It is **declarative**: the same image always produces the same SBOM (modulo the SBOM tool's version). It says nothing about whether anything is exploitable.

In this project: `syft` reads the OCI layers, walks the package databases (`dpkg`, `apk`, `rpm`, Python `RECORD`, Node `package.json`, Go `buildinfo`, etc.), and emits an SPDX-JSON document. It's uploaded as a GitHub Actions artifact alongside every signed image.

Why an SBOM matters even when there are zero known vulns:
- **Audit + license compliance** — "is this image GPL-2.0-clean?" is answered by the SBOM, not by the scanner.
- **0-day forensics** — when CVE-2026-XXXX drops next month, the SBOM lets you query "which of my historical images contained this package@version?" in seconds. The scanner can only tell you about the image you scan today.
- **Supply-chain attestation** — SLSA provenance and `cosign attest --predicate sbom.json` use the SBOM as a signed claim about image contents.

## Vulnerability scan

A **differential** between an inventory and a CVE database. It says nothing about license, structure, or contents — only "this version of this package has known CVE-XXXX of severity Y, here's the upgrade path."

In this project: `grype` consumes the same image (or, more efficiently, the SBOM), looks each package version up in the Anchore CVE feed, and produces a SARIF report. The pipeline is configured `severity-cutoff: high, fail-build: true` — HIGH or CRITICAL findings break the build before the image is pushed.

Why a vuln scan can't replace an SBOM:
- **Point-in-time** — scan results decay. An image that scanned clean yesterday is not necessarily clean today; the CVE database changes. The SBOM doesn't.
- **Coverage gaps** — scanners can't see vulnerabilities the database doesn't know about, packages they don't recognize, or vulns introduced by code rather than dependencies. The SBOM gives you a substrate to query against future intelligence sources.
- **No license signal** — a scanner won't flag an LGPL transitive that your legal team prohibits. The SBOM will.

## Why both, in the same pipeline, in this order

```
build → SBOM (inventory) → vuln scan (differential) → push → sign
```

The SBOM is generated first because the scan is faster and more reliable when fed an SBOM than when scanning the image cold. The scan acts as a **gate** — fail-build on HIGH+ stops the push. The SBOM is **archival** — it persists as a workflow artifact (and could be persisted as a `cosign attest` predicate, see `what-id-do-differently.md`) regardless of scan outcome, so a clean-today image stays queryable when next quarter's CVE drops.

## Reference

- SPDX 2.3 spec: <https://spdx.github.io/spdx-spec/>
- Anchore syft: <https://github.com/anchore/syft>
- Anchore grype: <https://github.com/anchore/grype>
- SLSA Provenance v1: <https://slsa.dev/spec/v1.0/provenance>
