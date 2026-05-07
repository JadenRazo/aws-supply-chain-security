provider "aws" {
  region = var.home_region

  assume_role {
    role_arn = "arn:aws:iam::${local.workloads_dev_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project     = "aws-supply-chain-security"
      ManagedBy   = "terraform"
      Owner       = var.owner_tag
      Environment = "dev"
      CostCenter  = "portfolio"
    }
  }
}
