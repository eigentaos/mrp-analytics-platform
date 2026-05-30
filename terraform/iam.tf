# Phase 0a-iv: GHA OIDC provider + scoped IAM roles for plan/apply.
#
# Two roles, deliberately separated:
#   - gha_plan  — trusted only by pull_request events; read-only policy
#   - gha_apply — trusted only by ref:refs/heads/main (exact, no wildcard);
#                 scoped write policy (no "*" Resources, no broad IAM)
#
# OIDC trust uses dynamic GitHub thumbprint via the tls provider (Sec-5).
# AWS no longer strictly enforces thumbprint match for GitHub's OIDC token,
# but the field is required by the AWS API.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# State-bucket KMS key ARN.
#
# IAM policies must scope to the key ARN (arn:...:key/<key-id>) not the
# alias ARN (arn:...:alias/<name>) — alias is a pointer; AWS evaluates
# permissions against the key itself.
#
# We hardcode rather than using data "aws_kms_alias" because that data
# source requires kms:ListAliases on Resource:* (account-scoped list op),
# which would force us to grant a broader permission than necessary. The
# key ARN is stable (bootstrap-managed, will never be re-created without
# explicit state surgery), so hardcoding is the lower-risk choice.
locals {
  tfstate_kms_key_arn = "arn:aws:kms:us-east-1:416153529907:key/b27a6ae7-5cad-4fde-a0bf-99ebb83b2c05"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ---------------------------------------------------------------------------
# gha_plan  — pull_request trigger only, read-only scope
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gha_plan" {
  name        = "mrp-analytics-platform-gha-plan"
  description = "GHA OIDC role for terraform plan (PR-triggered + main-branch scheduled drift; read-only)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # PR-triggered plan workflow (terraform-plan.yml)
        Sid       = "TrustPullRequests"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:pull_request"
          }
        }
      },
      {
        # Scheduled drift detection + workflow_dispatch (terraform-drift.yml).
        # Schedule + manual dispatch on main branch use ref:refs/heads/main
        # sub claim. Trust is read-only equivalent — gha_plan policy doesn't
        # grant writes, so widening sub trust only adds drift-detection
        # ability, not mutation capability.
        Sid       = "TrustMainBranchDriftRuns"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "gha_plan_readonly" {
  name        = "mrp-analytics-platform-gha-plan-readonly"
  description = "Read-only access for terraform plan: state backend + IAM read + prod bucket policy read for drift detection"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBackendRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::mrp-analytics-platform-tfstate-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::mrp-analytics-platform-tfstate-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Sid      = "StateLockManage"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.current.account_id}:table/mrp-analytics-platform-tflock"
      },
      {
        Sid      = "StateKmsRead"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = local.tfstate_kms_key_arn
      },
      {
        Sid    = "IamRead"
        Effect = "Allow"
        Action = ["iam:Get*", "iam:List*"]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mrp-analytics-platform-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/mrp-analytics-platform-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        ]
      },
      {
        Sid      = "ProdBucketPolicyDriftRead"
        Effect   = "Allow"
        Action   = ["s3:GetBucketPolicy", "s3:GetBucketVersioning", "s3:GetBucketEncryption"]
        Resource = "arn:aws:s3:::${var.prod_data_lake_bucket}"
      },
      {
        # Sub-phase 0a-v: assume prod_read role (read-only) for data source
        # refresh on prod bucket policy. Scoped to read role only — gha_plan
        # never needs write access (PR workflow doesn't apply).
        Sid      = "AssumeProdReadForDriftRead"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = var.prod_bucket_policy_read_role_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gha_plan" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = aws_iam_policy.gha_plan_readonly.arn
}

# ---------------------------------------------------------------------------
# gha_apply — main-branch only, scoped write
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gha_apply" {
  name        = "mrp-analytics-platform-gha-apply"
  description = "GHA OIDC role for terraform apply (main branch only, scoped writes)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "gha_apply_terraform" {
  name        = "mrp-analytics-platform-gha-apply-terraform"
  description = "Scoped writes for terraform apply: state backend + IAM (mrp-analytics-platform-* only) + OIDC provider"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBackendFull"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::mrp-analytics-platform-tfstate-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::mrp-analytics-platform-tfstate-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Sid      = "StateLockFull"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.current.account_id}:table/mrp-analytics-platform-tflock"
      },
      {
        Sid      = "StateKmsFull"
        Effect   = "Allow"
        Action   = "kms:*"
        Resource = local.tfstate_kms_key_arn
      },
      {
        Sid    = "IamManageProjectScoped"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mrp-analytics-platform-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/mrp-analytics-platform-*"
        ]
      },
      {
        Sid    = "IamOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      },
      {
        Sid      = "IamPassRoleProjectScoped"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mrp-analytics-platform-*"
      },
      {
        # Sub-phase 0a-v: assume both prod_admin (write) and prod_read (refresh)
        # roles for cross-account bucket policy management. apply path uses
        # both providers; prod_read is needed for the refresh that precedes apply.
        Sid    = "AssumeProdAdminAndReadForBucketPolicy"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          var.prod_bucket_policy_admin_role_arn,
          var.prod_bucket_policy_read_role_arn,
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gha_apply" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_terraform.arn
}
