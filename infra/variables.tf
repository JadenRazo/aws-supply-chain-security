variable "home_region" {
  description = "AWS region for the workload."
  type        = string
  default     = "us-west-2"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository that holds signed images."
  type        = string
  default     = "supply-chain-demo"
}

variable "notification_email" {
  description = "Email address that receives SNS alerts when ECR scan-on-push surfaces HIGH+ findings."
  type        = string
  default     = "jadenscottrazo@gmail.com"
}

variable "severity_threshold" {
  description = "Severity at or above which the Lambda publishes an SNS alert. One of CRITICAL, HIGH, MEDIUM, LOW. HIGH is the default — it includes CRITICAL."
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["CRITICAL", "HIGH", "MEDIUM", "LOW"], var.severity_threshold)
    error_message = "severity_threshold must be CRITICAL, HIGH, MEDIUM, or LOW."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the scan-findings Lambda."
  type        = number
  default     = 7
}

variable "owner_tag" {
  type    = string
  default = "jadenrazo"
}

variable "mgmt_account_id" {
  description = "Management account ID — source of GitHub Actions OIDC role used to push images. Read from SSM at apply time when possible; this is a fallback."
  type        = string
  default     = "569239324174"
}
