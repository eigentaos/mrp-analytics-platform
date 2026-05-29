variable "aws_region" {
  type        = string
  description = "AWS region (must be us-east-1 per SCP mrp-analytics-substrate-guard)"
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "SCP mrp-analytics-substrate-guard restricts this OU to us-east-1 only."
  }
}

variable "environment" {
  type        = string
  description = "Environment tag (substrate is single-environment by design)"
  default     = "substrate"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo path for OIDC trust (org/repo)"
  default     = "eigentaos/mrp-analytics-platform"
}

variable "prod_data_lake_bucket" {
  type        = string
  description = "Prod S3 bucket to grant cross-account read on (sub-phase 0a-v)"
  default     = "mrp-data-lake-prod-466231402318"
}

variable "prod_bucket_policy_admin_role_arn" {
  type        = string
  description = "ARN of the prod-account IAM role with s3:Put/Get/DeleteBucketPolicy on the data lake bucket. Created by parent-repo services/cross-account-grants SAM stack (mrp-cross-account-grants-prod), deployed 2026-05-29. Trusted by gha_apply + SSO admin."
  default     = "arn:aws:iam::466231402318:role/mrp-cross-account-grants-prod-data-lake-policy-admin"
}

variable "prod_bucket_policy_read_role_arn" {
  type        = string
  description = "ARN of the prod-account IAM role with s3:GetBucketPolicy ONLY. Used by the prod_read provider alias for data source refresh (gha_plan + gha_apply both assume). Created by parent-repo services/cross-account-grants SAM stack alongside the admin role."
  default     = "arn:aws:iam::466231402318:role/mrp-cross-account-grants-prod-data-lake-policy-read"
}

# Note: airflow_ec2_role_name + snowflake_storage_integration_role_name
# variables were considered for use in trusting future principals from the
# prod_data_lake_read role's assume_role_policy. Removed when AWS IAM
# rejected non-existent principal ARNs in trust policies (apply-time
# MalformedPolicyDocument). Role creation deferred to sub-phase 0b; bucket
# policy in 0a-v references the future role ARN directly (S3 accepts
# non-existent ARNs in bucket policies).
