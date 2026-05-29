# Phase 0a-iii: Terraform skeleton only.
#
# IAM roles for GHA OIDC (gha_plan, gha_apply) are added in sub-phase 0a-iv.
# Cross-account read role (prod_data_lake_read) + prod bucket policy merge
# are added in sub-phase 0a-v (depends on parent-repo SAM PR for prod_admin).

data "aws_caller_identity" "current" {}

# Defensive: refuse to plan/apply if state was somehow opened against the
# wrong account. Belt-and-suspenders given the S3 backend already pins the
# account via bucket name.
locals {
  expected_account_id = "416153529907"
}

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == local.expected_account_id
      error_message = "Account mismatch: state expects ${local.expected_account_id}, got ${data.aws_caller_identity.current.account_id}. Are you on the wrong AWS profile?"
    }
  }
}
