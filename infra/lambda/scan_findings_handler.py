"""ECR scan-on-push event handler.

Receives `aws.ecr` `ECR Image Scan` events from EventBridge, extracts the
severity counts, and publishes an SNS alert when CRITICAL/HIGH (configurable)
findings are present. Below threshold, the function logs and exits — keeping
the inbox quiet for clean images.

The severity gate is here (not in the EventBridge rule) because EventBridge
patterns can't express numeric comparisons on `finding-severity-counts.HIGH`.
"""

import json
import logging
import os
from typing import Any

import boto3

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

sns = boto3.client("sns")

SEVERITY_ORDER = ["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"]


def _at_or_above(severity: str, threshold: str) -> bool:
    return SEVERITY_ORDER.index(severity) >= SEVERITY_ORDER.index(threshold)


def _format_message(detail: dict[str, Any], region: str) -> tuple[str, str]:
    repo = detail.get("repository-name", "unknown")
    digest = detail.get("image-digest", "unknown")
    tags = detail.get("image-tags", []) or ["<untagged>"]
    counts = detail.get("finding-severity-counts", {})
    scan_status = detail.get("scan-status", "unknown")

    console_url = (
        f"https://{region}.console.aws.amazon.com/ecr/repositories/private/"
        f"{repo}/_/image/{digest}/scan-results?region={region}"
    )

    body = (
        f"ECR scan finished for {repo}\n"
        f"  status:    {scan_status}\n"
        f"  digest:    {digest}\n"
        f"  tags:      {', '.join(tags)}\n"
        f"  findings:  {json.dumps(counts, sort_keys=True)}\n"
        f"\n"
        f"Console:   {console_url}\n"
    )
    subject = f"[ECR scan] {repo} :: {counts.get('CRITICAL', 0)} crit / {counts.get('HIGH', 0)} high"
    # SNS subjects are capped at 100 chars
    return subject[:100], body


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    LOG.info("event=%s", json.dumps(event))

    detail = event.get("detail", {})
    counts = detail.get("finding-severity-counts", {}) or {}
    threshold = os.environ.get("SEVERITY_THRESHOLD", "HIGH")
    region = os.environ.get("ECR_CONSOLE_REGION", "us-west-2")
    topic_arn = os.environ["SNS_TOPIC_ARN"]

    above_threshold_total = sum(
        n for sev, n in counts.items() if sev in SEVERITY_ORDER and _at_or_above(sev, threshold)
    )

    if above_threshold_total == 0:
        LOG.info(
            "scan_clean repo=%s digest=%s threshold=%s counts=%s",
            detail.get("repository-name"),
            detail.get("image-digest"),
            threshold,
            counts,
        )
        return {"published": False, "reason": "below_threshold", "counts": counts}

    subject, body = _format_message(detail, region)
    response = sns.publish(TopicArn=topic_arn, Subject=subject, Message=body)
    LOG.info(
        "scan_alert_published message_id=%s repo=%s above_threshold_total=%d",
        response.get("MessageId"),
        detail.get("repository-name"),
        above_threshold_total,
    )
    return {"published": True, "message_id": response.get("MessageId"), "counts": counts}
