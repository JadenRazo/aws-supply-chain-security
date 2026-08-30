import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).parents[1] / "scan_findings_handler.py"
SPEC = importlib.util.spec_from_file_location("scan_findings_handler", MODULE_PATH)
handler_module = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(handler_module)


class ScanFindingsHandlerTests(unittest.TestCase):
    def setUp(self):
        self.event = {
            "detail": {
                "repository-name": "supply-chain-demo",
                "image-digest": "sha256:abc123",
                "image-tags": ["0123456789ab"],
                "scan-status": "COMPLETE",
                "finding-severity-counts": {"MEDIUM": 2, "HIGH": 1},
            }
        }

    def test_severity_order(self):
        self.assertTrue(handler_module._at_or_above("CRITICAL", "HIGH"))
        self.assertTrue(handler_module._at_or_above("HIGH", "HIGH"))
        self.assertFalse(handler_module._at_or_above("MEDIUM", "HIGH"))

    def test_below_threshold_does_not_require_sns_or_publish(self):
        event = {"detail": {**self.event["detail"], "finding-severity-counts": {"MEDIUM": 2}}}
        with patch.dict(os.environ, {"SEVERITY_THRESHOLD": "HIGH"}, clear=True):
            with patch.object(handler_module, "_publish") as publish:
                result = handler_module.handler(event, None)

        self.assertEqual(result["reason"], "below_threshold")
        self.assertFalse(result["published"])
        publish.assert_not_called()

    def test_high_finding_publishes_to_configured_topic(self):
        response = {"MessageId": "message-123"}
        env = {
            "SEVERITY_THRESHOLD": "HIGH",
            "ECR_CONSOLE_REGION": "us-west-2",
            "SNS_TOPIC_ARN": "arn:aws:sns:us-west-2:123456789012:findings",
        }
        with patch.dict(os.environ, env, clear=True):
            with patch.object(handler_module, "_publish", return_value=response) as publish:
                result = handler_module.handler(self.event, None)

        self.assertTrue(result["published"])
        self.assertEqual(result["message_id"], "message-123")
        topic, subject, body = publish.call_args.args
        self.assertEqual(topic, env["SNS_TOPIC_ARN"])
        self.assertLessEqual(len(subject), 100)
        self.assertIn("1 high", subject)
        self.assertIn("sha256:abc123", body)

    def test_unknown_severity_is_ignored(self):
        event = {"detail": {**self.event["detail"], "finding-severity-counts": {"UNKNOWN": 9}}}
        with patch.dict(os.environ, {"SEVERITY_THRESHOLD": "HIGH"}, clear=True):
            result = handler_module.handler(event, None)
        self.assertFalse(result["published"])

    def test_invalid_threshold_fails_closed(self):
        with patch.dict(os.environ, {"SEVERITY_THRESHOLD": "URGENT"}, clear=True):
            with self.assertRaisesRegex(ValueError, "unsupported SEVERITY_THRESHOLD"):
                handler_module.handler(self.event, None)


if __name__ == "__main__":
    unittest.main()
