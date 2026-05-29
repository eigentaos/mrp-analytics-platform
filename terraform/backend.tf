terraform {
  required_version = "1.7.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "mrp-analytics-platform-tfstate-416153529907"
    key            = "phase-0a/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "mrp-analytics-platform-tflock"
    encrypt        = true
    kms_key_id     = "alias/mrp-analytics-platform-tfstate"
  }
}
