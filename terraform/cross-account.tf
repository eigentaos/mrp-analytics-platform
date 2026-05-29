# Sub-phase 0a-v: substrate-side read role + cross-account bucket policy merge.
#
# REVISED FROM ORIGINAL PLAN: the original intent was to defer this role to
# sub-phase 0b ("dormant grant"), but AWS S3 — like IAM — rejects bucket
# policies that reference non-existent principal ARNs. So the role MUST
# exist when the bucket policy is written.
#
# Compromise:
# - Role exists in 0a-v with trust = substrate gha_apply (CI) + substrate
#   SSO AdministratorAccess (local/human). Same pattern as the OQ #3
#   prod_admin role.
# - Role policy is narrow: read-only on prod data-lake fred/*. Worst case
#   if gha_apply is compromised: attacker reads public FRED data. No
#   tenant-data exposure (DenyTenantPaths in bucket policy is the second
#   line of defense).
# - Sub-phase 0b will NARROW the trust to airflow-ec2 +
#   snowflake-storage-integration roles (the actual consumers) and remove
#   the gha_apply + SSO admin trust.
#
# Defense-in-depth: explicit DenyTenantPaths statement in the bucket policy
# guards against any tenant-scoped path being added under fred/ in the
# future.

# ---------------------------------------------------------------------------
# Substrate-side: read role for prod FRED data
# ---------------------------------------------------------------------------

resource "aws_iam_role" "prod_data_lake_read" {
  name        = "mrp-analytics-platform-prod-data-lake-read"
  description = "Substrate-side role for reading prod FRED data. 0a-v trust = gha_apply + SSO admin (narrowed to airflow-ec2 + snowflake-storage-integration in 0b)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SubstrateCiRead"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gha_apply.arn
        }
        Action = "sts:AssumeRole"
      },
      {
        Sid    = "SubstrateSsoAdminRead"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          ArnLike = {
            "aws:PrincipalArn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "prod_data_lake_read" {
  name = "read-prod-fred"
  role = aws_iam_role.prod_data_lake_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadFredObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.prod_data_lake_bucket}/fred/*"
      },
      {
        Sid      = "ListFredPrefix"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.prod_data_lake_bucket}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["fred/*", "fred"]
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Prod-side: bucket policy merge — additive on existing statements
# ---------------------------------------------------------------------------

# Read existing prod bucket policy through the prod_admin provider so we can
# merge instead of overwrite. OQ #3 SAM role grants s3:GetBucketPolicy.
data "aws_s3_bucket_policy" "existing_prod" {
  provider = aws.prod_admin
  bucket   = var.prod_data_lake_bucket
}

data "aws_iam_policy_document" "prod_bucket_additions" {
  statement {
    sid    = "MrpAnalyticsPlatformFredRead"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.prod_data_lake_read.arn]
    }
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${var.prod_data_lake_bucket}/fred/*"]
  }

  statement {
    sid    = "MrpAnalyticsPlatformListFred"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.prod_data_lake_read.arn]
    }
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.prod_data_lake_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["fred/*", "fred"]
    }
  }

  # Sec-7: explicit Deny on any tenant-scoped path. Belt-and-suspenders even
  # though SP-2 confirmed fred/ is currently CLEAN of tenant data.
  statement {
    sid    = "MrpAnalyticsPlatformDenyTenantPaths"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.prod_data_lake_read.arn]
    }
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.prod_data_lake_bucket}/*/org-*",
      "arn:aws:s3:::${var.prod_data_lake_bucket}/*/customer-*",
      "arn:aws:s3:::${var.prod_data_lake_bucket}/*/tenant-*",
      "arn:aws:s3:::${var.prod_data_lake_bucket}/*/user-upload*"
    ]
  }
}

locals {
  # IDEMPOTENCY: drop any statements from a prior apply (Sids prefixed with
  # MrpAnalyticsPlatform) before concatenating the canonical new set. Without
  # this filter, each terraform apply would accumulate statements because
  # data.aws_s3_bucket_policy reads the post-prior-apply state. With the
  # filter, the merge converges to the same 4-statement output regardless of
  # starting state (existing foreign statements preserved, our 3 statements
  # always set fresh).
  foreign_prod_statements = [
    for s in jsondecode(data.aws_s3_bucket_policy.existing_prod.policy).Statement :
    s if !startswith(try(s.Sid, ""), "MrpAnalyticsPlatform")
  ]
  new_prod_statements = jsondecode(data.aws_iam_policy_document.prod_bucket_additions.json).Statement

  merged_prod_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.foreign_prod_statements, local.new_prod_statements)
  })
}

# Pre-apply size check. AWS bucket policy max is 20480 bytes.
resource "terraform_data" "prod_policy_size_guard" {
  lifecycle {
    precondition {
      condition     = length(local.merged_prod_policy) < 18000
      error_message = "Merged prod bucket policy is ${length(local.merged_prod_policy)} bytes — approaching 20480 limit. Audit existing statements before proceeding."
    }
  }
}

resource "aws_s3_bucket_policy" "prod_data_lake" {
  provider = aws.prod_admin
  bucket   = var.prod_data_lake_bucket
  policy   = local.merged_prod_policy

  depends_on = [terraform_data.prod_policy_size_guard]
}
