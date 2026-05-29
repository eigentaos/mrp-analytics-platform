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
  description = "GHA OIDC role for terraform plan (PR-triggered, read-only)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
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
    }]
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
        Resource = "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:alias/mrp-analytics-platform-tfstate"
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
        Resource = "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:alias/mrp-analytics-platform-tfstate"
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gha_apply" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_terraform.arn
}
