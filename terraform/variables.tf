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
  description = "ARN of the prod-account IAM role with s3:PutBucketPolicy on the data lake bucket (sub-phase 0a-v; provided after parent-repo SAM PR lands)"
  default     = ""
}
