# Architecture

## Overview

This repo manages the **Track B analytics substrate** — a destroyable AWS sub-OU that hosts portfolio demo infrastructure for Snowflake, dbt, Airflow, MLflow, and Feast.

## Account & Org structure

| Resource | ID | Owner |
|---|---|---|
| Organization | `o-21de019fec` | mgmt account `466231402318` |
| Sub-OU `mrp-analytics-demo` | `ou-hibx-c9to7pnt` | mgmt account |
| Account `mrp-analytics-platform` | **`416153529907`** | this substrate |
| SCP `mrp-analytics-substrate-guard` | `p-angzwya4` | attached to sub-OU |

## Service Control Policy

The sub-OU SCP enforces three preventative guardrails:

1. **Region lock** — all non-IAM/non-global services restricted to `us-east-1`. Carve-outs: `iam:*`, `support:*`, `organizations:*`, `sts:*`, `cloudfront:*`, `route53:*`.
2. **Expensive-service block** — SageMaker, Redshift, RDS:Create*, OpenSearch, ElastiCache, KinesisAnalytics, Comprehend, Rekognition all denied. Prevents accidental SageMaker training spend or similar.
3. **No IAM users** — `iam:CreateUser` and `iam:CreateAccessKey` denied. Identity Center federation only.

SCP combines with the default `p-FullAWSAccess` policy via AWS Deny-wins semantics: full access *except* the explicit Deny list.

## Identity & access

| Mechanism | Used for |
|---|---|
| IAM Identity Center (`ssoins-7223354147eafe41`, owner `466231402318`) | Human interactive access via `AdministratorAccess` Permission Set (4h sessions) |
| GHA OIDC roles (added in sub-phase 0a-iv) | CI workflows: `gha_plan` (PRs, read-only) + `gha_apply` (main branch, scoped writes) |
| `OrganizationAccountAccessRole` | Break-glass from management account |
| `RootCredentialsManagement` org feature (enabled `2026-02-21`) | Centrally managed root credentials; no member-account root password |

**No long-lived IAM users exist in this account by design** (SCP `DenyIAMUserCreation`).

## State backend

| Resource | ID/Name | Notes |
|---|---|---|
| S3 bucket | `mrp-analytics-platform-tfstate-416153529907` | us-east-1; versioning Enabled; SSE-KMS via the key below (`BucketKeyEnabled: true` for cost); public-access-block all 4 flags `true` |
| KMS key | `b27a6ae7-5cad-4fde-a0bf-99ebb83b2c05` | Alias `alias/mrp-analytics-platform-tfstate`; default IAM-driven policy currently (will scope to GHA roles in 0a-iv) |
| DynamoDB lock table | `mrp-analytics-platform-tflock` | PK `LockID HASH`; `PAY_PER_REQUEST` |

### MFA Delete decision

MFA Delete is intentionally **not enabled** on the state bucket. The MFA Delete enablement flow requires the bucket-owner *root* user to pass an MFA token interactively, but Centralized Root Access removes the root password on this account by design.

Mitigating controls:

- SCP `DenyIAMUserCreation` blocks any IAM user creation
- Identity Center sessions are 4-hour bounded
- Terraform state is reproducible from re-apply
- Future lifecycle rules can prevent any deletion operations

If a future incident motivates MFA Delete, it can be enabled via the management-account privileged-session-as-root flow (`aws iam create-root-user-session`).

### State preservation across account closure

State is **co-located with the substrate** — if the account is closed (it's destroyable by design), state is lost with it. To preserve state across closures, add S3 cross-region replication to a management-account bucket. Not implemented in Phase 0a per the "destroyable by design" framing.

## Cross-account: prod data-lake read (sub-phase 0a-v)

A future sub-phase grants this account read access to `s3://mrp-data-lake-prod-466231402318/fred/*` for the Airflow + Snowflake ingestion DAGs added in 0b. The grant uses an explicit Deny on tenant-scoped paths (`*/org-*`, `*/customer-*`, `*/tenant-*`, `*/user-upload*`) for defense-in-depth even though the audit at 0a kickoff confirmed `fred/` is currently CLEAN of tenant data.

## CI/CD

| Workflow (added in 0a-iv) | Trigger | Role |
|---|---|---|
| `terraform-plan.yml` | `pull_request` to any branch | `gha_plan` (read-only via OIDC) |
| `terraform-apply.yml` | `push` to `main` | `gha_apply` (scoped writes via OIDC) |
| `terraform-drift.yml` | weekly cron | `gha_plan` — opens GH issue on `terraform plan -detailed-exitcode == 2` |

GHA OIDC trust patterns:
- `gha_plan` accepts `repo:eigentaos/mrp-analytics-platform:pull_request` (any PR)
- `gha_apply` accepts `repo:eigentaos/mrp-analytics-platform:ref:refs/heads/main` (exact, no wildcard)

## Conventions

### Managed vs inline IAM policies

- **`aws_iam_policy` + attachment** for policies attached to ≥2 roles or whose lifecycle differs from the role
- **`aws_iam_role_policy`** (inline) for policies bound 1:1 to a single role with no reuse

Phase 0a uses managed policies exclusively for OIDC roles so future Identity-Center Permission Sets can attach the same baseline.

### Region

Single region: `us-east-1`. SCP-enforced. Validated by `variable "aws_region"` precondition.

### Tags

All resources tagged via `provider.aws.default_tags`:

```
Project     = mrp-analytics-platform
Environment = substrate
ManagedBy   = terraform
Track       = B
```

Bootstrap resources tag `ManagedBy = terraform-bootstrap` to distinguish from sub-phase 0a-iv-and-later resources.

## Related

- **Parent plan**: `docs/superpowers/plans/2026-05-29-phase-0a-substrate-bootstrap.md` in `eigentaos/market-research-lean` (private, develop branch). Complete sub-phase sequence + DoD + decisions log lives there.
- **Analytics migration plan**: `docs/architecture/analytics-stack-migration-plan.md` in the same parent repo. Track A vs Track B framing, 2026-05-29 C-literal pivot.
