# =============================================================================
# Staging environment — real discovered IDs from phase0-inputs.md
# =============================================================================

aws_region     = "us-east-1"
aws_account_id = "382724554857"

# Image: updated by CI/CD pipeline on each deploy.
# Set to a placeholder — CI will pass -var="image=..." at apply time.
image = "382724554857.dkr.ecr.us-east-1.amazonaws.com/plant-api:latest"

# ECS sizing (staging: minimum viable)
cpu           = 256
memory        = 1024
desired_count = 1
min_capacity  = 1
max_capacity  = 2

# Networking — discovered values (phase0-inputs.md §2)
vpc_id     = "vpc-b97762de"
subnet_ids = ["subnet-7d57a227"] # Private A, us-east-1a — only private subnet

# Shared ALB SG and HTTPS listener (phase0-inputs.md §4)
alb_security_group_id = "sg-0ea89191a2ca2065a"
alb_listener_arn      = "arn:aws:elasticloadbalancing:us-east-1:382724554857:listener/app/ECHOcommunity-load-balancer/cda099b79e56784d/6f2b7bd42f572512"

# Staging host header — new subdomain (no existing rule; free to create)
host_headers           = ["plant-api-staging.echocommunity.org"]
listener_rule_priority = 17 # Free — verified: 1,5,8,9,10,11,12,13,14,15,16,18,50,120 used

# RDS — shared production RDS instance, staging database (phase0-inputs.md §5)
# The staging database and role are created out-of-band by:
#   infra/scripts/bootstrap-staging-db.sh
# That script also creates the secret rds/echocommunity-production/plantapi-staging-app.
# The ARN below is the EXPECTED ARN pattern; it will be the actual ARN once the
# script runs (Secrets Manager ARNs for named secrets follow this pattern).
# Run bootstrap-staging-db.sh BEFORE terraform apply for staging (see README).
rds_security_group_ids = ["sg-007ae20731af7483c", "sg-35fa1548"]
database_host          = "echocommunity-production.ceui3mx2fcbs.us-east-1.rds.amazonaws.com"
database_port          = 5432
# DATABASE_NAME is NOT injected as an env var — config/database.yml already
# hardcodes "Plant_API_staging" for the staging RAILS_ENV.

# Secrets Manager — staging DB credentials
# Created out-of-band by infra/scripts/bootstrap-staging-db.sh.
# Supply the full ARN here after the script runs; the suffix (-XXXXXX) is
# assigned by Secrets Manager at creation time — retrieve with:
#   aws secretsmanager describe-secret \
#     --secret-id rds/echocommunity-production/plantapi-staging-app \
#     --query ARN --output text
# Using an ARN variable (not a data source) so that terraform plan works
# before the secret exists.  Update this value after bootstrap-staging-db.sh
# completes and before running terraform apply.
db_secret_arn          = "arn:aws:secretsmanager:us-east-1:382724554857:secret:rds/echocommunity-production/plantapi-staging-app-XXXXXX"
db_secret_username_key = "username"
db_secret_password_key = "password"

# S3 — shared images bucket
images_s3_bucket = "images-us-east-1.echocommunity.org"

# CORS origins — include the admin SPA origins (update as needed)
cors_origins = "https://plant-api-staging.echocommunity.org,https://plant-admin-staging.echocommunity.org,http://localhost:5173"

# Observability
log_retention_days = 30

# Route53 — staging record managed by Terraform
route53_record_enabled = true
route53_zone_id        = "ZT83JIHVIK1D9"
route53_record_name    = "plant-api-staging.echocommunity.org"
alb_dns_name           = "ECHOcommunity-load-balancer-346078402.us-east-1.elb.amazonaws.com"
alb_zone_id            = "Z35SXDOTRQ7X7K" # Canonical hosted zone ID for the ALB (us-east-1)
