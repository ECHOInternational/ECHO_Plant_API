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
└── README.md           # This file
```

---

## Apply order

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

### Step 3 — Staging

```bash
cd infra/envs/staging
terraform init
terraform apply
```

### Step 4 — Production (creates the ECS stack but does NOT route live traffic)

```bash
cd infra/envs/production
terraform init
terraform apply
```

Production uses a **placeholder host header** (`plant-api-cutover.echocommunity.org`)
in its listener rule (priority 19). Live traffic continues to flow through the existing
EB rule (priority 15) until you perform the cutover below.

---

## Secret seeding

After each `terraform apply` for an environment, seed the three SSM SecureString
parameters. Terraform creates them with placeholder values and then ignores future
changes — you must set the real secrets via CLI or Console.

### Staging

```bash
ENV=staging
REGION=us-east-1

aws ssm put-parameter \
  --region $REGION \
  --name "/plant-api/${ENV}/DATABASE_USERNAME" \
  --value "plantapi_app" \
  --type SecureString \
  --overwrite

aws ssm put-parameter \
  --region $REGION \
  --name "/plant-api/${ENV}/DATABASE_PASSWORD" \
  --value "<the-real-password>" \
  --type SecureString \
  --overwrite

aws ssm put-parameter \
  --region $REGION \
  --name "/plant-api/${ENV}/APPLICATION_JWT_SECRET" \
  --value "<RSA-public-key-PEM>" \
  --type SecureString \
  --overwrite
```

### Production

```bash
ENV=production
# Same three commands as above with ENV=production and production credentials.
```

The `APPLICATION_JWT_SECRET` value is the RSA public key (PEM format) used to
verify JWTs issued by `www.echocommunity.org`. Retrieve the current value from
the EB environment variable `APPLICATION_JWT_SECRET` before decommissioning EB.

---

## Staging database

**There is no staging RDS instance.** Options (choose one before applying staging):

1. **Shared schema (simplest):** Create a separate database on the existing production
   RDS instance:
   ```sql
   CREATE DATABASE "Plant_API_staging" OWNER plantapi_app;
   ```
   The staging ECS tasks use `DATABASE_NAME=Plant_API_staging`. This isolates data
   at the database level but shares the same RDS instance and credentials.

2. **Snapshot restore (recommended for long-term):** Restore a snapshot of
   `Plant_API_production` to a new RDS instance. Update `database_host` in
   `envs/staging/terraform.tfvars` to the new endpoint before applying.

---

## Production cutover procedure

The existing ALB listener rule at **priority 15** currently forwards both
`plant-api.echocommunity.org` AND `echoplantapi.us-east-1.elasticbeanstalk.com`
to the EB target group (`awseb-echoplan-default-em2rm`).

After `terraform apply` for production, an ECS target group and a healthy ECS
service exist at priority 19 with a placeholder host. To cut over production traffic:

### Pre-cutover checklist

- [ ] Staging has been running successfully for at least 24 hours
- [ ] All SSM parameters seeded for production (`DATABASE_*`, `APPLICATION_JWT_SECRET`)
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

### Cutover (zero-downtime)

Get the new ECS target group ARN from Terraform output:

```bash
cd infra/envs/production
terraform output target_group_arn
```

Modify the existing priority-15 rule to forward to the new ECS target group:

```bash
NEW_TG_ARN="<output from above>"
RULE_ARN="<priority-15 rule ARN>"   # retrieve with: aws elbv2 describe-rules --listener-arn ...

aws elbv2 modify-rule \
  --rule-arn $RULE_ARN \
  --actions Type=forward,TargetGroupArn=$NEW_TG_ARN \
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
  --rule-arn $RULE_ARN \
  --actions Type=forward,TargetGroupArn=$EB_TG_ARN \
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
  (`i-03f65b4dc1516cef7`). If the NAT instance goes down, ECS tasks lose ECR/SSM
  connectivity. Consider replacing with an AWS Managed NAT Gateway.

- **SSM state locking**: uses Terraform 1.9+ native S3 locking (`use_lockfile = true`)
  — no DynamoDB table required.

- **Task image pinning**: `aws_ecs_service` has `lifecycle { ignore_changes = [task_definition] }`
  so that CI/CD pipeline updates to the task definition (via `aws ecs update-service`)
  are not reverted by Terraform. Run `terraform apply` only for infrastructure changes;
  image deploys are handled by the GitHub Actions pipeline.
