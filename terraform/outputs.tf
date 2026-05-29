output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Account ID this state was applied against"
}

output "region" {
  value       = var.aws_region
  description = "Region (always us-east-1 per SCP)"
}

output "gha_plan_role_arn" {
  value       = aws_iam_role.gha_plan.arn
  description = "ARN for the GHA terraform plan role (set as AWS_PLAN_ROLE_ARN secret)"
}

output "gha_apply_role_arn" {
  value       = aws_iam_role.gha_apply.arn
  description = "ARN for the GHA terraform apply role (set as AWS_APPLY_ROLE_ARN secret)"
}

output "github_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "GitHub OIDC provider ARN (referenced by future role trust policies)"
}
