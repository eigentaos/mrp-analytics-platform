output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Account ID this state was applied against"
}

output "region" {
  value       = var.aws_region
  description = "Region (always us-east-1 per SCP)"
}
