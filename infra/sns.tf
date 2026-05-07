resource "aws_sns_topic" "scan_findings" {
  name              = "ecr-scan-findings-${var.ecr_repository_name}"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.scan_findings.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
