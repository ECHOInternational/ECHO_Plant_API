# ECHO Plant API — ECS Infrastructure

Terraform infrastructure for migrating the ECHO Plant API from Elastic Beanstalk to Amazon ECS
(Fargate). All resources are in **us-east-1**, account **382724554857**.

---

## Directory layout

```
infra/
├── bootstrap/          # One-time: creates the S3 remote state bucket
├── global/             # ECR repo + GitHub Actions deploy IAM role
├── modules/
│   └── plant-api/      # Reusable ECS cluster, service, roles, SGs, ALB rule
├── envs/
│   ├── staging/        # Staging environment (plant-api-staging.echocommunity.org)
│   └── production/     # Production environment (plant-api.echocommunity.org)
├── scripts/
│   └── bootstrap-staging-db.sh  # One-time staging DB + secret creation
└── README.md           # This file
```

---

## Apply order

The full first-time ordering is:

```
Step 1: bootstrap TF (once only)
Step 2: global TF
Step 3: create write-profile / confirm credentials
Step 4: run bootstrap-staging-db.sh (from this machine, once RDS SG grants access)
Step 5: update staging db_secret_arn in terraform.tfvars
Step 6: seed APPLICATION_JWT_SECRET for both environments (see §Secrets below)
Step 7: terraform apply — staging
Step 8: terraform apply — production
Step 9: smoke-test staging; proceed to production cutover
```

### Step 1 — Bootstrap (once only)

Creates the S3 bucket used as remote state for all other modules.

```bash
cd infra/bootstrap
terraform init
terraform apply
```

The bootstrap uses **local state**. Commit or securely store the resulting
`terraform.tfstate` file — it is small but must not be lost.

### Step 2 — Global

Creates the ECR repository and the GitHub Actions deploy IAM role.

```bash
cd infra/global
terraform init
terraform apply
```

### Step 3 — Create write-profile / confirm credentials

You need an IAM profile with at minimum:
- `secretsmanager:GetSecretValue` on the RDS master secret
- `secretsmanager:CreateSecret`
- `secretsmanager:DescribeSecret`
- Standard Terraform permissions (S3 state bucket, ECS, IAM, etc.)

Confirm the profile works:

```bash
aws sts get-caller-identity --profile <your-write-profile>
```

### Step 4 — Run bootstrap-staging-db.sh

This script must be run **before** `terraform apply` for staging because staging's
Terraform config references the `rds/echocommunity-production/plantapi-staging-app`
Secrets Manager secret that the script creates.

**Pre-requisite:** Your machine (or the machine you run this on) must be able to reach
`echocommunity-production.ceui3mx2fcbs.us-east-1.rds.amazonaws.com:5432`.
The RDS instance is `PubliclyAccessible: true`, so you just need your source IP
allowed inbound in `sg-007ae20731af7483c` or `sg-35fa1548` (default SG).

```bash
AWS_PROFILE=<your-write-profile> ./infra/scripts/bootstrap-staging-db.sh
```

The script is idempotent (safe to re-run). It:
1. Retrieves the RDS master credentials from Secrets Manager secret
   `rds!db-65c1ca5f-392b-47ef-b6f1-e71c13c5b512`.
2. Creates database `Plant_API_staging` and role `plantapi_staging_app` if they
   do not already exist.
3. Grants all privileges and loads `db/structure.sql` as the new role.
4. Stores `{"username":"plantapi_staging_app","password":"<generated>"}` in
   Secrets Manager as `rds/echocommunity-production/plantapi-staging-app`.

After it completes, retrieve the secret ARN and update staging tfvars:

```bash
STAGING_ARN="$(aws secretsmanager describe-secret \
  --secret-id rds/echocommunity-production/plantapi-staging-app \
  --query ARN --output text \
  --profile <your-write-profile>)"
echo "Update db_secret_arn in infra/envs/staging/terraform.tfvars to: $STAGING_ARN"
```

Edit `infra/envs/staging/terraform.tfvars` and replace the placeholder
`arn:aws:secretsmanager:...:rds/echocommunity-production/plantapi-staging-app-XXXXXX`
with the real ARN.

### Step 5 — Seed secrets (APPLICATION_JWT_SECRET and SECRET_KEY_BASE)

Terraform creates two per-env Secrets Manager secrets with placeholder values
and then ignores future changes:
- `plant-api-<env>/application-jwt-secret` — RSA public key for JWT verification
- `plant-api-<env>/secret-key-base` — Rails SECRET_KEY_BASE (**required to boot**)

Seed both secrets before the first deploy.  The ECS task definition injects them
as `APPLICATION_JWT_SECRET` and `SECRET_KEY_BASE` respectively.

#### Production APPLICATION_JWT_SECRET

Retrieve the current value from EB and store it in the new secret:

```bash
# Replace <REDACTED> with the actual PEM value from the EB env var
aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id "plant-api-production/application-jwt-secret" \
  --secret-string "<RSA-public-key-PEM>" \
  --profile <your-write-profile>
```

#### Staging APPLICATION_JWT_SECRET

The staging RSA public key is the same as production (same IdP); copy it from
the sibling `echo-seeds-staging/application-jwt-secret` secret without printing
the value:

```bash
# Pipe get | put — the value is never displayed in the terminal
aws secretsmanager get-secret-value \
  --region us-east-1 \
  --secret-id "echo-seeds-staging/application-jwt-secret" \
  --query SecretString \
  --output text \
  --profile <your-write-profile> \
| aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id "plant-api-staging/application-jwt-secret" \
  --secret-string "$(cat /dev/stdin)" \
  --profile <your-write-profile>
```

#### SECRET_KEY_BASE — staging

Generate a fresh random value (this is an API-only app with no cookies or
encrypted session data, so there is no continuity requirement):

```bash
SECRET=$(openssl rand -hex 64)
aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id "plant-api-staging/secret-key-base" \
  --secret-string "$SECRET" \
  --profile <your-write-profile>
unset SECRET
```

#### SECRET_KEY_BASE — production

**Option A (recommended if you want zero cutover risk):** Reuse the current EB
`SECRET_KEY_BASE` value.  This preserves any encrypted cookies or session tokens
in flight during the cutover window.  Retrieve it from the EB console before
decommissioning EB, then seed it:

```bash
# Replace <REDACTED> with the EB env var value
aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id "plant-api-production/secret-key-base" \
  --secret-string "<REDACTED>" \
  --profile <your-write-profile>
```

**Option B (acceptable for this API):** Generate a fresh value.  Because this
app is API-only with JWT authentication and no browser cookies, rotating
SECRET_KEY_BASE has no user-visible impact (no sessions to invalidate):

```bash
SECRET=$(openssl rand -hex 64)
aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id "plant-api-production/secret-key-base" \
  --secret-string "$SECRET" \
  --profile <your-write-profile>
unset SECRET
```

### Step 6 — Staging apply

```bash
cd infra/envs/staging
terraform init
terraform apply
```

`terraform apply` creates the ECS service immediately. **The service will
crash-loop until (a) the container image exists in ECR and (b) the migration
task has run.**  Follow the staging first-boot sequence below before expecting
the service to stabilise.

#### Staging first-boot sequence (after `terraform apply`)

1. **Push the container image** to ECR so the task definition can pull it:
   ```bash
   # From the repo root — adjust the tag as needed
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin \
     382724554857.dkr.ecr.us-east-1.amazonaws.com
   docker build -t plant-api:staging .
   docker tag plant-api:staging \
     382724554857.dkr.ecr.us-east-1.amazonaws.com/plant-api:staging
   docker push 382724554857.dkr.ecr.us-east-1.amazonaws.com/plant-api:staging
   ```

2. **Run the migration task once** (the web tasks will fail `/health` while
   pending migrations exist — the healthcheck blocks traffic until migrations
   complete):
   ```bash
   # Retrieve the tasks security group ID from Terraform output first:
   TASKS_SG="$(cd infra/envs/staging && terraform output -raw tasks_security_group_id)"
   aws ecs run-task \
     --cluster plant-api-staging \
     --task-definition plant-api-staging-migrate \
     --launch-type FARGATE \
     --network-configuration "awsvpcConfiguration={subnets=[subnet-7d57a227],securityGroups=[$TASKS_SG],assignPublicIp=DISABLED}" \
     --region us-east-1
   # Wait for the task to exit (exit code 0 = success):
   aws ecs wait tasks-stopped \
     --cluster plant-api-staging \
     --tasks "<task-arn-from-run-task-output>" \
     --region us-east-1
   ```

3. **The ECS service's next task launch** will pull the image, connect to the
   migrated database, and pass `/health`.  The deployment circuit breaker will
   stop crash-looping once a healthy task is running.

> **Note:** An alternative to step 2 is setting `desired_count = 0` in
> `terraform.tfvars` before the first `terraform apply`, then running the
> migration task, then bumping `desired_count` back to 1.  The run-task
> approach above requires no tfvars edits and is preferred.

### Step 7 — Production apply (creates ECS stack; does NOT route live traffic)

```bash
cd infra/envs/production
terraform init
terraform apply
```

Production uses a **placeholder host header** (`plant-api-cutover.echocommunity.org`)
in its listener rule (priority 19). Live traffic continues to flow through the existing
EB rule (priority 15) until you perform the cutover below.

---

## Secrets

### How secrets are managed

This infrastructure uses **AWS Secrets Manager** with the per-app scoped convention
already established in the account (`rds/echocommunity-production/` prefix).

| Secret name | Type | Who creates | Terraform action |
|---|---|---|---|
| `rds/echocommunity-production/plantapi-app` | JSON (`username`/`password`) | EXISTING (pre-created) | `data` source via ARN variable |
| `rds/echocommunity-production/plantapi-staging-app` | JSON (`username`/`password`) | `bootstrap-staging-db.sh` | ARN variable (no data source; must exist before apply) |
| `plant-api-production/application-jwt-secret` | Plain string (PEM) | Terraform (placeholder) | `resource` with `lifecycle { ignore_changes = [secret_string] }` |
| `plant-api-staging/application-jwt-secret` | Plain string (PEM) | Terraform (placeholder) | `resource` with `lifecycle { ignore_changes = [secret_string] }` |
| `plant-api-production/secret-key-base` | Plain string (hex) | Terraform (placeholder) | `resource` with `lifecycle { ignore_changes = [secret_string] }` |
| `plant-api-staging/secret-key-base` | Plain string (hex) | Terraform (placeholder) | `resource` with `lifecycle { ignore_changes = [secret_string] }` |

### JSON key names — VERIFY BEFORE FIRST APPLY

The task definition references `rds/echocommunity-production/plantapi-app` with
JSON-key selectors:

```
valueFrom = "<secret-arn>:username::"   # DATABASE_USERNAME
valueFrom = "<secret-arn>:password::"   # DATABASE_PASSWORD
```

The key names `username` / `password` match the house convention seen in sibling
secrets (`discourse-app`, `echocommunity-app`, etc.) and the description
"Scoped DB role plantapi_app". **However**, you cannot verify the actual key names
with the `ReadOnlyAccess` profile (it lacks `GetSecretValue`).

Before first apply, use a write-capable profile to confirm:

```bash
aws secretsmanager get-secret-value \
  --secret-id rds/echocommunity-production/plantapi-app \
  --query SecretString \
  --output text \
  --profile <your-write-profile>
```

The output will be JSON such as `{"username":"plantapi_app","password":"..."}`.
If the key names differ from `username` / `password`, update:
- `infra/envs/production/terraform.tfvars`:  `db_secret_username_key` / `db_secret_password_key`
- `infra/envs/staging/terraform.tfvars`:     same variables

### KMS keys

All secrets in the `rds/echocommunity-production/` prefix and the
`plant-api-<env>/` secrets use the **AWS managed default key** (KmsKeyId = null,
verified via `DescribeSecret`). No `kms:Decrypt` IAM statement is required in the
execution role — `secretsmanager:GetSecretValue` is sufficient.

---

## Staging database

The staging database `Plant_API_staging` lives on the shared production RDS instance
(`echocommunity-production`). It is owned by a dedicated app role `plantapi_staging_app`
with credentials stored in `rds/echocommunity-production/plantapi-staging-app`.

**No `DATABASE_NAME` env var is injected** into the ECS task: `config/database.yml`
already hardcodes `Plant_API_staging` for `RAILS_ENV=staging`, so the env var
is redundant and has been removed to avoid any risk of value divergence.

The staging database is created by `infra/scripts/bootstrap-staging-db.sh` (see
§Apply order above). The Terraform staging config references the secret ARN as a
plain variable (not a `data "aws_secretsmanager_secret"` data source) so that
`terraform plan` works before the secret exists. Update `db_secret_arn` in
`infra/envs/staging/terraform.tfvars` after the bootstrap script runs.

---

## Production cutover procedure

The existing ALB listener rule at **priority 15** currently forwards both
`plant-api.echocommunity.org` AND `echoplantapi.us-east-1.elasticbeanstalk.com`
to the EB target group (`awseb-echoplan-default-em2rm`).

After `terraform apply` for production, an ECS target group and a healthy ECS
service exist at priority 19 with a placeholder host. To cut over production traffic:

### Pre-cutover checklist

- [ ] `rds/echocommunity-production/plantapi-app` JSON key names confirmed (`username`/`password`)
- [ ] `plant-api-production/application-jwt-secret` seeded with the real RSA public key PEM
- [ ] `plant-api-production/secret-key-base` seeded (see §Secrets — choose Option A or B)
- [ ] Staging has been running successfully for at least 24 hours
- [ ] `rails db:migrate` run against the production database via the migration task:
  ```bash
  aws ecs run-task \
    --cluster plant-api-production \
    --task-definition plant-api-production-migrate \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-7d57a227],securityGroups=[<tasks-sg-id>],assignPublicIp=DISABLED}" \
    --region us-east-1
  ```
- [ ] ECS service health check passes (target group shows healthy targets)
- [ ] Smoke-tested via the placeholder domain `plant-api-cutover.echocommunity.org`

### Smoke test (pre-cutover)

```bash
curl -s https://plant-api-cutover.echocommunity.org/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ plants(first: 1) { totalCount } }"}' | python3 -m json.tool
```

### Cutover (zero-downtime)

Get the new ECS target group ARN from Terraform output:

```bash
cd infra/envs/production
terraform output target_group_arn
```

Retrieve the existing priority-15 rule ARN:

```bash
LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:382724554857:listener/app/ECHOcommunity-load-balancer/cda099b79e56784d/6f2b7bd42f572512"
RULE_ARN="$(aws elbv2 describe-rules \
  --listener-arn "$LISTENER_ARN" \
  --region us-east-1 \
  --query "Rules[?Priority=='15'].RuleArn" \
  --output text)"
```

Modify the priority-15 rule to forward to the ECS target group:

```bash
NEW_TG_ARN="<output from terraform output target_group_arn>"

aws elbv2 modify-rule \
  --rule-arn "$RULE_ARN" \
  --actions "Type=forward,TargetGroupArn=$NEW_TG_ARN" \
  --region us-east-1
```

This is atomic and instant. The Route53 A record already points to the shared ALB,
so no DNS change is needed.

### Rollback

If the cutover needs to be reversed, swap rule 15's action back to the original
EB target group:

```bash
EB_TG_ARN="arn:aws:elasticloadbalancing:us-east-1:382724554857:targetgroup/awseb-echoplan-default-em2rm/b85fa4d81a6e1217"

aws elbv2 modify-rule \
  --rule-arn "$RULE_ARN" \
  --actions "Type=forward,TargetGroupArn=$EB_TG_ARN" \
  --region us-east-1
```

The EB environment remains running until explicitly terminated — keep it available
for at least 48 hours after cutover.

---

## Architecture notes

- **Single private subnet** (`subnet-7d57a227`, us-east-1a): all ECS tasks run here
  following the existing house pattern. There is no HA across AZs for compute.
  Multi-AZ private subnets are a future improvement.

- **NAT**: Outbound internet from the private subnet routes through a NAT EC2 instance
  (`i-03f65b4dc1516cef7`). If the NAT instance goes down, ECS tasks lose ECR/Secrets
  Manager connectivity. Consider replacing with an AWS Managed NAT Gateway.

- **S3 state locking**: uses Terraform 1.9+ native S3 locking (`use_lockfile = true`)
  — no DynamoDB table required.

- **Task image pinning**: `aws_ecs_service` has `lifecycle { ignore_changes = [task_definition] }`
  so that CI/CD pipeline updates to the task definition (via `aws ecs update-service`)
  are not reverted by Terraform. Run `terraform apply` only for infrastructure changes;
  image deploys are handled by the GitHub Actions pipeline.

- **RAILS_ENV vs DATABASE_NAME**: `config/database.yml` hardcodes the database name
  per `RAILS_ENV` (`Plant_API_production` and `Plant_API_staging`). The task definition
  sets `RAILS_ENV` correctly (production or staging) and omits `DATABASE_NAME` to avoid
  redundancy and potential misconfiguration.

- **Application Auto Scaling service-linked role**: The ECS auto-scaling
  (`aws_appautoscaling_target`) requires the
  `AWSServiceRoleForApplicationAutoScaling_ECSService` service-linked role.  This
  role **already exists in account 382724554857** (verified via
  `iam:GetRole AWSServiceRoleForApplicationAutoScaling_ECSService`).  No manual
  creation or Terraform import is needed.

- **RDS master-secret KMS key**: The RDS master secret
  (`rds!db-65c1ca5f-392b-47ef-b6f1-e71c13c5b512`) is encrypted with customer-managed
  KMS key **`2dd2633c-5b82-4526-9c58-80d154ba3821`** (verified live via
  `describe-db-instances` on `echocommunity-production`).  The deploy policy
  (`docs/iam/claude-deploy-policy.json`) includes a `KmsDecryptForRdsMasterSecret`
  statement granting `kms:Decrypt` on that key, conditioned on
  `kms:ViaService: secretsmanager.us-east-1.amazonaws.com`.  The ECS execution role
  does **not** need this key — the execution role only reads the scoped app-role secret
  (`plantapi-app` / `plantapi-staging-app`), which uses the AWS-managed default key
  (`KmsKeyId: null`, verified via `DescribeSecret`).
