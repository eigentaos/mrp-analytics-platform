# Phase 0a-ii bootstrap: import existing state-backend resources.
#
# These resources were created imperatively from the SSO admin profile during
# sub-phase 0a-ii (before any Terraform config existed). This config imports
# them so Terraform manages them going forward — drift detection covers the
# state backend itself.
#
# To bootstrap: see docs/RUNBOOK-recover-from-failed-apply.md "Bootstrap state
# needs re-import" section for the terraform import commands.

resource "aws_kms_key" "tfstate" {
  description             = "Terraform state encryption for mrp-analytics-platform substrate (Phase 0a)"
  enable_key_rotation     = false
  deletion_window_in_days = 30

  # Phase 0a-vi tighten: replace default IAM-driven policy (kms:* to root
  # principal — lets ANY IAM principal with matching IAM perms use the key)
  # with an explicit allowlist. Default behavior was acceptable for bootstrap
  # but bypasses the principle of explicit scope.
  #
  # 4 statements:
  # 1. EnableRootKeyManagement — root can MANAGE the key (PutKeyPolicy,
  #    ScheduleKeyDeletion, Tag, etc.) but NOT use it for crypto. Safety net
  #    so the key can never be locked unmanageable.
  # 2. AllowUseByCiRoles — gha_plan + gha_apply explicit usage. Future IAM
  #    roles in the account don't inherit access by accident.
  # 3. AllowUseBySsoAdmin — SSO AdministratorAccess Permission Set pattern;
  #    operator's local terraform apply works.
  # 4. AllowBreakGlassByOrgAccountAccessRole — management-account-controlled
  #    role assumed via create-root-user-session etc. Last-resort recovery.
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "tfstate-scoped-0a-vi"
    Statement = [
      {
        Sid       = "EnableRootKeyManagement"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::416153529907:root" }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
          "kms:ReplicateKey",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowUseByCiRoles"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::416153529907:role/mrp-analytics-platform-gha-apply",
            "arn:aws:iam::416153529907:role/mrp-analytics-platform-gha-plan",
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowUseBySsoAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::416153529907:root" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "aws:PrincipalArn" = "arn:aws:iam::416153529907:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*"
          }
        }
      },
      {
        Sid    = "AllowBreakGlassByOrgAccountAccessRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::416153529907:role/OrganizationAccountAccessRole"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:PutKeyPolicy",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/mrp-analytics-platform-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "mrp-analytics-platform-tfstate-416153529907"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
    # mfa_delete intentionally omitted — Centralized Root Access removes the
    # root password needed for the enable flow; mitigated by SCP
    # DenyIAMUserCreation + 4h SSO sessions + reproducible state.
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  name         = "mrp-analytics-platform-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
