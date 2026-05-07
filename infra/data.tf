data "aws_ssm_parameter" "account_map" {
  provider = aws.mgmt
  name     = "/sre-landing-zone/account-map"
}

locals {
  account_map              = jsondecode(data.aws_ssm_parameter.account_map.value)
  workloads_dev_account_id = local.account_map["workloads_dev"]
}

provider "aws" {
  alias  = "mgmt"
  region = var.home_region
  # No assume_role — uses the ambient identity. CI assumes the mgmt OIDC role
  # before terraform runs; locally, this is the user's mgmt-account credentials.
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
