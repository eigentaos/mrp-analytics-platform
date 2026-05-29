provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mrp-analytics-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
      Track       = "B"
    }
  }
}

# Sub-phase 0a-v: prod_admin provider for cross-account bucket policy management.
# Assumes the prod-account IAM role created by parent-repo SAM service
# services/cross-account-grants/template.yaml (mrp-cross-account-grants-prod stack).
# Role grants only s3:Put/Get/DeleteBucketPolicy on the data-lake bucket; cannot
# read bucket contents or touch any other resource.
provider "aws" {
  alias  = "prod_admin"
  region = var.aws_region

  assume_role {
    role_arn     = var.prod_bucket_policy_admin_role_arn
    session_name = "mrp-analytics-platform-tf-bucket-policy"
  }

  default_tags {
    tags = {
      Project     = "mrp-analytics-platform"
      Environment = "substrate"
      ManagedBy   = "terraform-cross-account"
      Track       = "B"
    }
  }
}
