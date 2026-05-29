# Runbook: recover from a failed Terraform apply

Common failure modes and recovery paths. Use the `mrp-analytics-platform` SSO profile for all commands unless noted.

## State is locked (DynamoDB lock not released)

A previous apply crashed without releasing the lock, or a parallel apply is in progress.

```bash
aws dynamodb scan --table-name mrp-analytics-platform-tflock --profile mrp-analytics-platform
# Identify the lock entry; verify nobody else is actively applying
terraform force-unlock <LOCK_ID>
```

Only force-unlock if you've confirmed no other apply is in flight — concurrent applies corrupt state.

## State diverged from reality (resource changed outside Terraform)

For a single resource changed via Console/CLI:

```bash
terraform refresh    # pulls actual state into Terraform's view
terraform plan       # see the drift
# Either: re-apply via Terraform to revert
# Or: import the changed config into Terraform
```

For a resource that was deleted out-of-band:

```bash
terraform state rm <addr>    # tell Terraform it no longer exists
terraform apply              # re-create
```

## Apply partially succeeded (some resources created, some failed)

Terraform updates state for what succeeded before crashing. Retries are usually safe.

```bash
terraform plan      # see what's left
terraform apply     # complete the work
```

If a specific resource is wedged in a bad state:

```bash
terraform taint <addr>
terraform apply       # destroys + re-creates
```

## OIDC role assume fails immediately after first apply

Eventual consistency: AWS may take 30–60s after `aws_iam_openid_connect_provider` creation before STS can resolve the new federated principal. First GHA workflow run after the OIDC provider is created may fail with `InvalidIdentityToken`. Retry succeeds.

## KMS NotFoundException on state write

Same eventual consistency: KMS key may not be visible to S3 immediately after `aws_kms_key` creation. Wait 60s, retry.

## Bootstrap state needs re-import

If `phase-0a/bootstrap/terraform.tfstate` in the state bucket is lost (deletable but versioned, so usually recoverable from previous versions):

```bash
cd terraform/bootstrap
terraform init
terraform import aws_kms_key.tfstate b27a6ae7-5cad-4fde-a0bf-99ebb83b2c05
terraform import aws_kms_alias.tfstate alias/mrp-analytics-platform-tfstate
terraform import aws_s3_bucket.tfstate mrp-analytics-platform-tfstate-416153529907
terraform import aws_s3_bucket_versioning.tfstate mrp-analytics-platform-tfstate-416153529907
terraform import aws_s3_bucket_server_side_encryption_configuration.tfstate mrp-analytics-platform-tfstate-416153529907
terraform import aws_s3_bucket_public_access_block.tfstate mrp-analytics-platform-tfstate-416153529907
terraform import aws_dynamodb_table.tflock mrp-analytics-platform-tflock
terraform plan       # expect: no changes
```

If S3 versioning has the prior state, recover that instead:

```bash
aws s3api list-object-versions --bucket mrp-analytics-platform-tfstate-416153529907 \
  --prefix phase-0a/bootstrap/terraform.tfstate
aws s3api get-object --bucket mrp-analytics-platform-tfstate-416153529907 \
  --key phase-0a/bootstrap/terraform.tfstate \
  --version-id <VERSION_ID> /tmp/prior-state.tfstate
# Inspect, then put it back as current:
aws s3 cp /tmp/prior-state.tfstate s3://mrp-analytics-platform-tfstate-416153529907/phase-0a/bootstrap/terraform.tfstate
```

## Phase 0a main state needs re-import

Same pattern as bootstrap. Resources to import are defined in `terraform/main.tf` (Phase 0a-iv adds the OIDC + IAM role resources).

## Account is locked out (no SSO access, no root password)

Centralized Root Access escape hatch from the management account (`466231402318`):

```bash
AWS_PROFILE=default aws iam create-root-user-session \
  --target-account-id 416153529907 \
  --duration-seconds 3600
```

Returns temporary root credentials. Use sparingly — audit-logged in CloudTrail. Revert to Identity Center after the incident.

If Identity Center itself is unreachable, the management account's Identity Center admin can re-assign the `AdministratorAccess` Permission Set:

```bash
AWS_PROFILE=default aws sso-admin create-account-assignment \
  --instance-arn arn:aws:sso:::instance/ssoins-7223354147eafe41 \
  --target-id 416153529907 --target-type AWS_ACCOUNT \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-7223354147eafe41/ps-72238d6935467132 \
  --principal-type USER --principal-id <user-id>
```

## State file corrupted

S3 versioning + 90-day default lifecycle (none currently set; consider adding) means prior versions of state are recoverable.

```bash
aws s3api list-object-versions --bucket mrp-analytics-platform-tfstate-416153529907 \
  --prefix phase-0a/terraform.tfstate \
  --query "Versions[*].[VersionId,LastModified,Size]" --output table
# Identify the last-known-good version
aws s3api copy-object --bucket mrp-analytics-platform-tfstate-416153529907 \
  --copy-source "mrp-analytics-platform-tfstate-416153529907/phase-0a/terraform.tfstate?versionId=<VERSION_ID>" \
  --key phase-0a/terraform.tfstate
```

## When to escalate

- Apply leaves resources in an unknown state and `terraform refresh` doesn't resolve
- State file is corrupted AND all prior S3 versions are also corrupted
- IAM permissions wedged such that both Identity Center and GHA OIDC are unreachable
- SCP edits accidentally lock the account out of all useful APIs (rare — SCPs apply to all OU members; revert from management account)

Document the incident in `incidents/` (add the directory as needed) with timeline + commands run + outcome.
