terraform {
  required_version = "1.7.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  # Bootstrap state is kept in the same bucket but under a separate key so
  # it can be re-imported if lost. The chicken-and-egg (bucket holds its own
  # state) is acceptable because the bucket existed before this config did:
  # if it's destroyed we re-create with the imperative commands in
  # docs/RUNBOOK-recover-from-failed-apply.md and re-import.
  backend "s3" {
    bucket         = "mrp-analytics-platform-tfstate-416153529907"
    key            = "phase-0a/bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "mrp-analytics-platform-tflock"
    encrypt        = true
    kms_key_id     = "alias/mrp-analytics-platform-tfstate"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "mrp-analytics-platform"
      Environment = "substrate"
      ManagedBy   = "terraform-bootstrap"
      Track       = "B"
    }
  }
}
