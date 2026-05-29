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

# Sub-phase 0a-v: prod_admin provider for cross-account bucket policy WRITE.
# Assumes the prod-account IAM role created by parent-repo SAM service
# services/cross-account-grants/template.yaml (mrp-cross-account-grants-prod
# stack, admin role). Role grants only s3:Put/Get/DeleteBucketPolicy on the
# data-lake bucket. Trusted by substrate gha_apply + SSO admin only.
provider "aws" {
  alias  = "prod_admin"
  region = var.aws_region

  assume_role {
    role_arn     = var.prod_bucket_policy_admin_role_arn
    session_name = "mrp-analytics-platform-tf-bucket-policy-write"
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

# Sub-phase 0a-v: prod_read provider for the data.aws_s3_bucket_policy
# refresh path. Assumes the prod-account READ-ONLY role (separate from
# admin) so substrate gha_plan (PR workflow) can refresh state without
# write access. Trusted by gha_plan + gha_apply + SSO admin.
provider "aws" {
  alias  = "prod_read"
  region = var.aws_region

  assume_role {
    role_arn     = var.prod_bucket_policy_read_role_arn
    session_name = "mrp-analytics-platform-tf-bucket-policy-read"
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
