resource "aws_cloudwatch_event_rule" "ecr_scan" {
  name        = "ecr-scan-${var.ecr_repository_name}"
  description = "Routes ECR scan-on-push completion events for ${var.ecr_repository_name} to the scan-findings Lambda."

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Scan"]
    detail = {
      scan-status     = ["COMPLETE"]
      repository-name = [var.ecr_repository_name]
    }
  })
}

resource "aws_cloudwatch_event_target" "scan_findings" {
  rule = aws_cloudwatch_event_rule.ecr_scan.name
  arn  = aws_lambda_function.scan_findings.arn
}

resource "aws_lambda_permission" "events_invoke" {
  statement_id  = "AllowEventBridgeInvokeScanFindings"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scan_findings.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_scan.arn
}
