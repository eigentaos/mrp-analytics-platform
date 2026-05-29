# mrp-analytics-platform

Track B analytics substrate (Snowflake + dbt + Airflow + MLflow + Feast) on a destroyable AWS sub-OU. Terraform + GitHub Actions.

[![Terraform Plan](https://github.com/eigentaos/mrp-analytics-platform/actions/workflows/terraform-plan.yml/badge.svg)](.github/workflows/terraform-plan.yml)
[![Terraform Drift](https://github.com/eigentaos/mrp-analytics-platform/actions/workflows/terraform-drift.yml/badge.svg)](.github/workflows/terraform-drift.yml)

> **Note:** GitHub Actions workflows are added in sub-phase 0a-iv once GHA OIDC IAM roles + secrets exist. Until then, the badges show "no status."

## What this is

A **destroyable** AWS account dedicated to the "Track B" data-platform demo. Snowflake trial → dbt → Airflow on EC2 → MLflow → Feast, all under a regional/cost-bounded sub-OU. The substrate exists to:

- Prove portfolio-grade data-platform competence without coupling it to production multi-tenant systems
- Absorb ingestion-substrate work that the C-literal pivot (2026-05-29) un-deferred from the parent migration plan
- Isolate Snowflake / dbt / Airflow experimentation from the production OLTP path

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — account, sub-OU, SCP, state backend, IAM model
- [`docs/RUNBOOK-recover-from-failed-apply.md`](docs/RUNBOOK-recover-from-failed-apply.md) — disaster recovery procedures
- Parent plan + Phase 0a sequence lives in a separate private repo

## Phase status

| Phase | Status |
|---|---|
| 0a-i (sub-OU + SCP + account) | complete |
| 0a-ii (Identity Center bootstrap + state backend) | complete |
| 0a-iii (repo + Terraform skeleton + docs) | in this commit |
| 0a-iv (Terraform IAM + GHA OIDC + secrets + workflows) | pending |
| 0a-v (cross-account read on prod data lake) | pending |
| 0a-vi (drift detection + docs polish) | pending |

## Local development

Authenticate via IAM Identity Center (replace `<...>` with the values from `docs/ARCHITECTURE.md`):

```ini
# Append to ~/.aws/config
[sso-session mrp-org-sso]
sso_start_url = <portal-url>
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile mrp-analytics-platform]
sso_session = mrp-org-sso
sso_account_id = <account-id>
sso_role_name = AdministratorAccess
region = us-east-1
output = json
```

```bash
aws sso login --sso-session mrp-org-sso
aws sts get-caller-identity --profile mrp-analytics-platform   # verify
cd terraform && terraform init && terraform plan
```

## License

MIT — see [LICENSE](LICENSE).
