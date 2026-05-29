# Changelog

## 2026-05-29 — Initial skeleton (sub-phase 0a-iii)

**Added:**
- README.md, LICENSE (MIT), .gitignore (Terraform standard)
- `terraform/` Phase 0a skeleton: `backend.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`
- `terraform/bootstrap/`: imports the state-backend resources created imperatively in sub-phase 0a-ii so Terraform manages them going forward
- `docs/ARCHITECTURE.md`: account, sub-OU, SCP, state backend, IAM model
- `docs/RUNBOOK-recover-from-failed-apply.md`: disaster recovery procedures
- `CHANGELOG.md`: this file

**Pre-existing (created out-of-band in sub-phases 0a-i and 0a-ii):**
- AWS account `416153529907` under sub-OU `ou-hibx-c9to7pnt` with SCP `p-angzwya4`
- IAM Identity Center `AdministratorAccess` Permission Set assignment for user `rcampos`
- State backend: KMS key `b27a6ae7-...`, S3 bucket `mrp-analytics-platform-tfstate-416153529907`, DynamoDB table `mrp-analytics-platform-tflock`

**Deferred to sub-phase 0a-iv:**
- `terraform/main.tf` IAM resources: `aws_iam_openid_connect_provider.github`, `aws_iam_role.gha_plan` + `gha_apply`, scoped managed policies
- `.github/workflows/terraform-plan.yml`, `terraform-apply.yml`, `terraform-drift.yml`
- GHA secrets: `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`
- Tightening KMS key policy to scope GHA roles only (removing default IAM-driven access)

**Deferred to sub-phase 0a-v:**
- `aws_iam_role.prod_data_lake_read` + cross-account bucket policy merge on `mrp-data-lake-prod-466231402318`
- Gated on parent-repo SAM PR adding the `prod_admin` IAM role to the prod account

**Deferred to sub-phase 0a-vi:**
- Drift detection workflow verification
- Final docs polish + parent-repo migration plan changelog update
