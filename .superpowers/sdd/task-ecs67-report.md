# Task ECS 6–7: Terraform Infrastructure Report

**Date:** 2026-07-09
**Branch:** `ecs-migration`

---

## Status

All Terraform modules pass `terraform init -backend=false && terraform validate` and
`terraform fmt -check -recursive` with zero errors. One warning was present in bootstrap
(missing `filter {}` on lifecycle rule) and was fixed before final validation.

---

## Validation summary

| Module | init -backend=false | validate | fmt |
|---|---|---|---|
| bootstrap | PASS | PASS | PASS |
| global | PASS | PASS | PASS |
| modules/plant-api | PASS | PASS | PASS |
| envs/staging | PASS | PASS | PASS |
| envs/production | PASS | PASS | PASS |

---

## What was built

### `infra/bootstrap/`
- S3 bucket `echo-plant-api-terraform-state-382724554857` (versioned, SSE-AES256, public-block-all, 90-day noncurrent expiration)
- Local state only (bootstrapping constraint)
- README with one-time apply instructions

### `infra/global/`
- ECR repository `plant-api` (IMMUTABLE tags, scan-on-push, lifecycle: keep last 25 tagged + expire untagged >14d)
- Data-sourced GitHub OIDC provider (existing ARN: `arn:aws:iam::382724554857:oidc-provider/token.actions.githubusercontent.com`)
- IAM role `gha-plant-api-deploy` with trust restricted to `ECHOInternational/ECHO_Plant_API` on `ref:refs/heads/master`, `environment:staging`, `environment:production`
- Inline policy: ECR push to plant-api repo only; ECS Register/Describe/Update/RunTask conditioned on the two clusters; iam:PassRole scoped to `plant-api-*-task-role` + `plant-api-*-execution-role` name patterns; CloudWatch Logs read on `/ecs/plant-api-*`
- S3 backend: `global/terraform.tfstate`

### `infra/modules/plant-api/`
Complete reusable module. Resources per env instantiation:
- `aws_ecs_cluster` (`plant-api-<env>`) with Container Insights + FARGATE/FARGATE_SPOT capacity providers
- `aws_cloudwatch_log_group` `/ecs/plant-api-<env>` with configurable retention
- Three `aws_ssm_parameter` (DATABASE_USERNAME, DATABASE_PASSWORD, APPLICATION_JWT_SECRET) with placeholder values + `lifecycle { ignore_changes = [value] }`
- IAM execution role (`plant-api-<env>-execution-role`): AmazonECSTaskExecutionRolePolicy + SSM GetParameters + KMS Decrypt on `alias/aws/ssm`
- IAM task role (`plant-api-<env>-task-role`): S3 Put/GetObject/DeleteObject/ListBucket on the images bucket
- ECS tasks security group: ingress port 3000 from ALB SG only; egress all
- `aws_vpc_security_group_ingress_rule` resources on each provided RDS SG (5432 from tasks SG) — rule-only additions, never adopt the SGs themselves
- Web task definition: X86_64/LINUX, awslogs, 15 env vars (non-secret), 3 SSM secrets, container health check
- Migration task definition: same image/roles, command `["bundle","exec","rails","db:migrate"]`, separate family for `run-task` use
- ALB target group: port 3000, `/health` check, 30s deregistration delay, `create_before_destroy`
- ALB listener rule on the shared HTTPS listener (host-header condition, configurable priority)
- Optional Route53 A-alias record (disabled for production since record already exists)
- ECS service: Fargate, circuit breaker + rollback, 60s grace period, private subnet, `assignPublicIp=false`; `lifecycle { ignore_changes = [task_definition, desired_count] }` so CI/CD deploys don't get reverted
- App autoscaling: CPU target-tracking at 70%, configurable min/max

### `infra/envs/staging/`
- Real discovered IDs baked into `terraform.tfvars`
- ALB listener rule priority **17** (verified free; used priorities: 1,5,8,9,10,11,12,13,14,15,16,18,50,120)
- Host header: `plant-api-staging.echocommunity.org`
- Route53 A-alias record managed (`route53_record_enabled = true`) — new subdomain, no prior record
- CPU 256, memory 1024, desired 1, max 2
- Database: `Plant_API_staging` on shared production RDS (create out-of-band; see README)
- Log retention: 30 days

### `infra/envs/production/`
- Real discovered IDs baked into `terraform.tfvars`
- ALB listener rule priority **19** (verified free) with **placeholder host** `plant-api-cutover.echocommunity.org`
- This rule is INACTIVE for live traffic until cutover (see README)
- Route53 record NOT managed (`route53_record_enabled = false`) — existing A-alias record preserved
- CPU 512, memory 1024, desired 2, min 2, max 6
- Database: `Plant_API_production` on the existing RDS instance
- Log retention: 90 days
- Cutover documented in `infra/README.md`: modify existing priority-15 rule action to forward to the new ECS TG via `aws elbv2 modify-rule`

---

## Key decisions / concerns

### 1. ECS condition on `iam:ECS:cluster` for GHA role
The `ecs:RunTask` + `ecs:UpdateService` permissions use `Condition: ArnLike { ecs:cluster }`.
Note that `ecs:RegisterTaskDefinition` and `ecs:DescribeTaskDefinition` are account-level
(no cluster resource scope available) — `resources = ["*"]` is required for those two
actions. This is standard AWS behavior for ECS task definition operations.

### 2. Single private subnet — single AZ
Only `subnet-7d57a227` (us-east-1a) exists as a private subnet. All tasks run in one AZ.
Multi-AZ HA is a future infra improvement (add private subnets in us-east-1b/c + update
the `subnet_ids` list in tfvars).

### 3. Production cutover strategy — priority 19 with placeholder host
Rather than trying to import the existing EB rule (risky; would need careful import targeting)
or creating a Terraform resource that conflicts with the EB rule, the approach is:
- Terraform owns a NEW rule (priority 19, placeholder host) — no import needed
- The EB rule (priority 15) is modified manually at cutover time using `aws elbv2 modify-rule`
- Rollback is instant by restoring the EB TG ARN

Priority 14 (`transition.echocommunity.org`) and 16 (EB path rule) are taken;
17 was chosen for staging, 19 for production, skipping 18 (`edn.link`).

### 4. RDS SG ingress rules
The module creates `aws_vpc_security_group_ingress_rule` resources ADDING rules to the
existing RDS security groups (`sg-007ae20731af7483c`, `sg-35fa1548`). These are rule
additions only — Terraform does not adopt or manage the SGs themselves. This is the
correct pattern for shared SGs.

### 5. S3 state locking
Uses Terraform 1.9+ native S3 locking (`use_lockfile = true`) — no DynamoDB table
needed. Requires Terraform >= 1.9 on all workstations and CI runners.

### 6. `DATABASE_NAME` env var
The EB app used `DATABASE_HOST/PORT/USERNAME/PASSWORD` but not `DATABASE_NAME`.
The Rails database.yml likely reads from ENV or has it hardcoded. The Terraform module
passes `DATABASE_NAME` explicitly — the Dockerfile/entrypoint may need to reference it
in `config/database.yml` (use `<%= ENV.fetch("DATABASE_NAME", "Plant_API_production") %>`).
Verify before first deploy.

### 7. No `SANDBOX` vars in task definition
Per spec: `SANDBOX` and `SANDBOX_TRUST_LEVEL` are excluded from the ECS task definition.
These are development-only bypass vars and must never appear in production or staging ECS configs.

### 8. KMS key scope for SSM SecureString
The execution role grants `kms:Decrypt` on `alias/aws/ssm` (the AWS-managed key used
by SSM SecureString by default). If the account uses a customer-managed KMS key for SSM,
the KMS key ARN will need updating in the execution role policy.

---

## Files created

```
infra/
├── README.md
├── bootstrap/
│   ├── README.md
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── global/
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── modules/
│   └── plant-api/
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
├── envs/
│   ├── staging/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   └── production/
│       ├── main.tf
│       ├── outputs.tf
│       ├── terraform.tfvars
│       └── variables.tf
```

`.dockerignore` already contained `infra/` — no change needed.

---

## Redesign: secrets manager

**Date:** 2026-07-09
**Commit:** see below

### What changed

#### 1. SSM parameters — removed entirely
All three `aws_ssm_parameter` resources (DATABASE_USERNAME, DATABASE_PASSWORD,
APPLICATION_JWT_SECRET) and the associated IAM policy (`execution_ssm` —
SSMGetParameters + KMSDecryptSSM on `alias/aws/ssm`) have been deleted from
`modules/plant-api/main.tf`.  Output `ssm_parameter_prefix` removed from all
outputs files.

#### 2. Secrets Manager — task secrets
The task definition `secrets` block now references Secrets Manager:

| Secret | Type | Env | Source |
|---|---|---|---|
| DATABASE_USERNAME | JSON key selector | production | EXISTING `rds/echocommunity-production/plantapi-app` (data via ARN var) |
| DATABASE_PASSWORD | JSON key selector | production | same |
| DATABASE_USERNAME | JSON key selector | staging | NEW `rds/echocommunity-production/plantapi-staging-app` (ARN var; created by bootstrap script) |
| DATABASE_PASSWORD | JSON key selector | staging | same |
| APPLICATION_JWT_SECRET | whole-value | both | NEW `plant-api-<env>/application-jwt-secret` (TF resource with placeholder + `lifecycle { ignore_changes = [secret_string] }`) |

valueFrom format for JSON-key secrets:
```
"<secret-arn>:username::"   # DATABASE_USERNAME
"<secret-arn>:password::"   # DATABASE_PASSWORD
```

JSON key names default to `username` / `password` (matching house convention
confirmed by sibling secret descriptions and the `rds/echocommunity-production/`
prefix pattern). Made configurable via module variables `db_secret_username_key`
/ `db_secret_password_key` with prominent verification note in README.

#### 3. KMS — no statement needed
`aws secretsmanager describe-secret` on `plantapi-app` returned `KmsKeyId: null`.
All sibling secrets (`discourse-app`, `echocommunity-app`, `spree-app`, etc.) also
have `KmsKeyId: null`.  All use the AWS managed default key.  Therefore no
`kms:Decrypt` IAM statement is required, and none was added.

#### 4. Execution role — updated
Old: `ssm:GetParameters/GetParameter/GetParametersByPath` + `kms:Decrypt on alias/aws/ssm`
New: `secretsmanager:GetSecretValue` scoped to exactly two ARNs:
- `var.db_secret_arn` (the RDS-scoped secret)
- `aws_secretsmanager_secret.jwt.arn` (the Terraform-managed JWT secret)

Policy resource renamed `execution_ssm` → `execution_secrets`,
inline policy `ssm-read-<env>` → `secretsmanager-read-<env>`.

#### 5. Staging DB — plain ARN variable (not data source)
The staging secret `rds/echocommunity-production/plantapi-staging-app` does not
exist until `bootstrap-staging-db.sh` creates it.  Using a `data` source would
make `terraform plan` fail before the script runs.  Instead, `db_secret_arn` is a
plain string variable in tfvars with a placeholder ARN suffix (`-XXXXXX`) and a
comment instructing the operator to update it after the script runs.

#### 6. DATABASE_NAME removed
`config/database.yml` hardcodes `Plant_API_production` and `Plant_API_staging`
per `RAILS_ENV`; confirmed staging.rb exists and sets `RAILS_ENV=staging`.
Injecting `DATABASE_NAME` as an env var was redundant and removed from:
- `local.base_env` in the module
- `database_name` variable in the module and both env configs
- `terraform.tfvars` in both envs
- The README no longer mentions it as a prerequisite

#### 7. New file: infra/scripts/bootstrap-staging-db.sh
Executable (chmod +x), 230 lines, heavily commented.  Disciplines:
- `set -euo pipefail`; no `set -x`
- Secret values held only in shell vars; never passed to `echo`
- All progress messages use fixed strings with no values
- Idempotency guards on DB, role, and secret existence
- Steps: fetch master secret → generate password (openssl rand -base64 32) →
  CREATE DATABASE → CREATE ROLE → GRANT + default privs → store secret in SM →
  load db/structure.sql as the new role
- Uses `python3` for JSON parsing (no `jq` dependency)
- `bash -n` passed; `shellcheck` not installed in this environment

#### 8. infra/README.md — fully revised
- Full 9-step ordering (bootstrap → global → credentials → bootstrap-staging-db.sh
  → update db_secret_arn → seed JWT secrets → staging apply → production apply → smoke)
- §Secrets table showing all four secrets, their type, creator, and TF action
- JSON key name verification instructions with write-profile command
- KMS note (no CMK, no kms:Decrypt needed)
- Staging JWT seed via get|put pipe (no value ever displayed)
- Production JWT seed command with redaction note
- Staging database section updated to reflect dedicated role and no DATABASE_NAME
- All SSM references removed

### Validation results

| Module | fmt | validate |
|---|---|---|
| bootstrap | PASS | PASS |
| global | PASS | PASS |
| modules/plant-api | PASS | PASS |
| envs/staging | PASS | PASS |
| envs/production | PASS | PASS |

`terraform fmt -check -recursive`: exit 0
`bash -n infra/scripts/bootstrap-staging-db.sh`: OK

### AWS data verified

| Check | Result |
|---|---|
| `rds/echocommunity-production/plantapi-app` exists | YES — ARN: `arn:aws:secretsmanager:us-east-1:382724554857:secret:rds/echocommunity-production/plantapi-app-tNMZMM` |
| KmsKeyId on plantapi-app | null (AWS managed key) |
| All sibling secrets KmsKeyId | null — confirmed for discourse-app, echocommunity-app, spree-app, echocommunity-staging-app |
| RDS master secret ARN | `arn:aws:secretsmanager:us-east-1:382724554857:secret:rds!db-65c1ca5f-392b-47ef-b6f1-e71c13c5b512-4hLpM3` |
| `echo-seeds-staging/application-jwt-secret` exists | YES — used as staging JWT source in README pipe command |
| `config/environments/staging.rb` exists | YES — RAILS_ENV=staging will activate it; database.yml `staging:` block hardcodes `Plant_API_staging` |

### Remaining operator actions (before first apply)

1. Use write-profile to verify JSON keys inside `rds/echocommunity-production/plantapi-app`
   (`get-secret-value` → confirm `username`/`password` or update tfvars).
2. Run `infra/scripts/bootstrap-staging-db.sh` (needs RDS SG inbound + write-profile).
3. Update `db_secret_arn` in `infra/envs/staging/terraform.tfvars` with the real ARN suffix.
4. Seed `plant-api-production/application-jwt-secret` from EB env var.
5. Seed `plant-api-staging/application-jwt-secret` via the get|put pipe in README.
6. Seed `plant-api-<env>/secret-key-base` (see README §Secrets for both options).
7. Apply staging, then production.

---

## Fix: final review findings

**Date:** 2026-07-09
**Commit:** see below

### C1 — SECRET_KEY_BASE missing from task definitions

Added `aws_secretsmanager_secret.secret_key_base` + `aws_secretsmanager_secret_version.secret_key_base_placeholder` to `infra/modules/plant-api/main.tf` following the exact pattern of the existing `jwt` secret:
- Name: `plant-api-<env>/secret-key-base`
- Placeholder value `PLACEHOLDER_CHANGE_ME` + `lifecycle { ignore_changes = [secret_string] }`
- Added `SECRET_KEY_BASE` entry to `local.task_secrets` (used by both `aws_ecs_task_definition.web` and `aws_ecs_task_definition.migrate`)
- Added `local.secret_key_base_arn` to `local.execution_secret_arns` so the execution role's `GetSecretValue` policy covers it

README §Secrets updated:
- Secrets table: two new rows for `plant-api-production/secret-key-base` and `plant-api-staging/secret-key-base`
- New seed instructions: staging (`openssl rand -hex 64`), production (Option A: reuse EB value; Option B: fresh generate — both documented with rationale)
- Pre-cutover checklist: added `plant-api-production/secret-key-base` seeded item

### C2 — Deploy policy missing EC2 describe reads

Added `Ec2DescribeForTerraform` statement to `docs/iam/claude-deploy-policy.json` with `ec2:DescribeSecurityGroups`, `DescribeSecurityGroupRules`, `DescribeVpcs`, `DescribeVpcAttribute`, `DescribeSubnets`, `DescribeNetworkInterfaces`, `DescribeTags`, `DescribeAvailabilityZones` on `Resource: *`, conditioned on `aws:RequestedRegion: us-east-1` (matching sibling statements).

Full policy audit against remaining Terraform refresh reads: elbv2 describes present; route53 gets present; logs describes present; ecs describes present; secretsmanager `DescribeSecret` + `GetSecretValue` on `plant-api-*` prefix covers both new secrets; `application-autoscaling:Describe*` present; `sts:GetCallerIdentity` always-allowed. No other gaps found.

### I2 — bootstrap-staging-db.sh: pgcrypto extension fails as app role

Restructured step 5 in `infra/scripts/bootstrap-staging-db.sh`:
- Step 5a: `CREATE EXTENSION IF NOT EXISTS pgcrypto;` executed AS THE MASTER USER against `$STAGING_DB` before loading structure.sql
- Step 5b: Load `db/structure.sql` as the app role (the `IF NOT EXISTS` guard makes the extension line in structure.sql a no-op)
- Comment documents the grep result: only one `CREATE EXTENSION` in structure.sql (line 16, pgcrypto); no `ALTER SYSTEM` or `COPY FROM` statements found
- No-echo discipline preserved: master_password and schema_password never passed to echo

### I3 — Staging first-boot ordering

Added "Staging first-boot sequence" subsection immediately after "Step 6 — Staging apply" in `infra/README.md`:
- Note that `terraform apply` creates the service which will crash-loop until image exists + migrations ran
- Three numbered steps: (1) push image to ECR, (2) run migration task via `aws ecs run-task` + `aws ecs wait tasks-stopped`, (3) service stabilises on next task launch
- Note on alternative approach (desired_count=0 first) with recommendation for the run-task path

### I1/I4 — Autoscaling SLR and RDS KMS key (documentation only)

Added two bullet points to Architecture notes in `infra/README.md`:
- **Autoscaling SLR**: explicitly states `AWSServiceRoleForApplicationAutoScaling_ECSService` already exists in account 382724554857 (live-verified), no manual creation needed
- **RDS master-secret KMS key**: documents KMS key `2dd2633c-5b82-4526-9c58-80d154ba3821` live-verified via `describe-db-instances`; explains why execution role does not need it (app-role secrets use AWS-managed default key, KmsKeyId null)

### M1 — Commit .terraform.lock.hcl files

Removed the `**/.terraform.lock.hcl` ignore line from `infra/.gitignore` (replaced with comment explaining lock files ARE committed). Added all four lock files via `git add -f`:
- `infra/bootstrap/.terraform.lock.hcl`
- `infra/global/.terraform.lock.hcl`
- `infra/envs/staging/.terraform.lock.hcl`
- `infra/envs/production/.terraform.lock.hcl`
- `infra/modules/plant-api/.terraform.lock.hcl`

All pin `hashicorp/aws` version `5.100.0`.

### M2 — Remove unused `container_env_overrides` variable

- Removed `variable "container_env_overrides"` from `infra/modules/plant-api/variables.tf`
- Replaced `merge(...)` local with direct `container_environment = local.base_env` in `infra/modules/plant-api/main.tf`
- Neither env's `main.tf` passed this variable, so no env-level changes needed

### Validation results

| Check | Result |
|---|---|
| `terraform fmt -check -recursive infra/` | PASS (exit 0) |
| `terraform validate` bootstrap | PASS |
| `terraform validate` global | PASS |
| `terraform validate` modules/plant-api | PASS |
| `terraform validate` envs/staging | PASS |
| `terraform validate` envs/production | PASS |
| `bash -n infra/scripts/bootstrap-staging-db.sh` | OK |
| `python3 -c "import json; json.load(open('docs/iam/claude-deploy-policy.json'))"` | JSON valid |
