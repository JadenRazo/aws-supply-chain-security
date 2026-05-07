data "archive_file" "scan_findings_handler" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/scan_findings_handler.zip"
}

resource "aws_iam_role" "scan_findings" {
  name = "scan-findings-handler-${var.ecr_repository_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scan_findings" {
  role = aws_iam_role.scan_findings.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishScanFindings"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.scan_findings.arn
      },
      {
        Sid    = "DescribeImageScans"
        Effect = "Allow"
        Action = [
          "ecr:DescribeImageScanFindings",
          "ecr:DescribeImages"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${local.workloads_dev_account_id}:log-group:/aws/lambda/${aws_lambda_function.scan_findings.function_name}:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "scan_findings" {
  name              = "/aws/lambda/scan-findings-${var.ecr_repository_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "scan_findings" {
  function_name = "scan-findings-${var.ecr_repository_name}"
  role          = aws_iam_role.scan_findings.arn
  handler       = "scan_findings_handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.scan_findings_handler.output_path
  source_code_hash = data.archive_file.scan_findings_handler.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN      = aws_sns_topic.scan_findings.arn
      SEVERITY_THRESHOLD = var.severity_threshold
      ECR_CONSOLE_REGION = data.aws_region.current.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.scan_findings]
}
