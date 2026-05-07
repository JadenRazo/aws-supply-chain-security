output "ecr_repository_uri" {
  description = "Full ECR repository URI. Use for docker push / cosign sign."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.app.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.scan_findings.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.scan_findings.function_name
}

output "eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.ecr_scan.name
}

output "post_apply_action" {
  description = "Reminder for the operator after apply."
  value       = <<-EOT

    POST-APPLY ACTION REQUIRED:

    SNS sent a confirmation email to ${var.notification_email}.
    Click the 'Confirm subscription' link in that email — until you do,
    SNS will silently drop alert messages.

    Verify subscription state:
      aws sns list-subscriptions-by-topic \
        --topic-arn ${aws_sns_topic.scan_findings.arn}

    Look for SubscriptionArn != "PendingConfirmation".
  EOT
}
