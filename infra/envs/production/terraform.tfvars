# =============================================================================
# Production environment — real discovered IDs from phase0-inputs.md
# =============================================================================

aws_region     = "us-east-1"
aws_account_id = "382724554857"

# Image: updated by CI/CD pipeline on each deploy.
image = "382724554857.dkr.ecr.us-east-1.amazonaws.com/plant-api:latest"

# ECS sizing (production: 2 tasks minimum)
cpu           = 512
memory        = 1024
desired_count = 2
min_capacity  = 2
max_capacity  = 6

# Networking (phase0-inputs.md §2)
vpc_id     = "vpc-b97762de"
subnet_ids = ["subnet-7d57a227"] # Private A, us-east-1a — only private subnet

# Shared ALB SG and HTTPS listener (phase0-inputs.md §4)
alb_security_group_id = "sg-0ea89191a2ca2065a"
alb_listener_arn      = "arn:aws:elasticloadbalancing:us-east-1:382724554857:listener/app/ECHOcommunity-load-balancer/cda099b79e56784d/6f2b7bd42f572512"

# CUTOVER STRATEGY:
#   The existing priority-15 rule currently forwards plant-api.echocommunity.org
#   traffic to the EB target group (awseb-echoplan-default-em2rm).
#
#   This Terraform config creates a new target group + listener rule at priority 19
#   with a PLACEHOLDER host header (plant-api-cutover.echocommunity.org). This rule
#   is INACTIVE for live traffic until you perform the cutover (see infra/README.md).
#
#   Cutover is accomplished by modifying ONLY the existing priority-15 rule's action
#   to forward to the new ECS target group — no DNS change required since the Route53
#   A record already points to this ALB. See infra/README.md for the exact command.
host_headers           = ["plant-api-cutover.echocommunity.org"]
listener_rule_priority = 19 # Free — verified: 1,5,8,9,10,11,12,13,14,15,16,18,50,120 used

# RDS — production database (phase0-inputs.md §5)
rds_security_group_ids = ["sg-007ae20731af7483c", "sg-35fa1548"]
database_host          = "echocommunity-production.ceui3mx2fcbs.us-east-1.rds.amazonaws.com"
database_port          = 5432
database_name          = "Plant_API_production"

# S3 — shared images bucket
images_s3_bucket = "images-us-east-1.echocommunity.org"

# CORS origins — production
cors_origins = "https://plant-api.echocommunity.org,https://plant-admin.echocommunity.org"

# Observability — 90 days for production
log_retention_days = 90

# Route53 — production record already exists as a Route53 A-alias to the shared ALB.
# Do NOT manage it here; Terraform would destroy the existing record on apply.
route53_record_enabled = false
