# ============================================================================
# Core
# ============================================================================

variable "env" {
  description = "Environment name (staging or production)"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.env)
    error_message = "env must be 'staging' or 'production'."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

# ============================================================================
# Container image
# ============================================================================

variable "image" {
  description = "Full container image URI (e.g. 382724554857.dkr.ecr.us-east-1.amazonaws.com/plant-api:v1.0.0)"
  type        = string
}

# ============================================================================
# ECS sizing
# ============================================================================

variable "cpu" {
  description = "Task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of ECS service tasks"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum tasks for autoscaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum tasks for autoscaling"
  type        = number
  default     = 4
}

# ============================================================================
# Networking
# ============================================================================

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the shared ALB (used to scope ingress to port 3000)"
  type        = string
}

variable "alb_listener_arn" {
  description = "ARN of the HTTPS listener on the shared ALB"
  type        = string
}

variable "host_headers" {
  description = "List of host-header values for the ALB listener rule"
  type        = list(string)
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule (must be unique across all rules)"
  type        = number
}

# ============================================================================
# RDS
# ============================================================================

variable "rds_security_group_ids" {
  description = "Security group IDs attached to the RDS instance (ingress rule added to each)"
  type        = list(string)
}

variable "database_host" {
  description = "RDS endpoint hostname (non-secret)"
  type        = string
}

variable "database_port" {
  description = "RDS port (non-secret)"
  type        = number
  default     = 5432
}

# ============================================================================
# Secrets Manager — DB credentials
# ============================================================================

variable "db_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret that holds the database credentials.

    For production: the EXISTING secret rds/echocommunity-production/plantapi-app
      (ARN: arn:aws:secretsmanager:us-east-1:382724554857:secret:rds/echocommunity-production/plantapi-app-tNMZMM)

    For staging: the NEW secret rds/echocommunity-production/plantapi-staging-app
      created out-of-band by infra/scripts/bootstrap-staging-db.sh.  Supply its ARN
      as a variable so terraform plan works before the secret exists.

    IMPORTANT: verify the actual JSON key names in the secret before first apply
    (see db_secret_username_key / db_secret_password_key variables below).
  EOT
  type        = string
}

variable "db_secret_username_key" {
  description = <<-EOT
    JSON key name for the database username inside the db_secret_arn secret.

    The house convention for rds/echocommunity-production/* scoped-role secrets
    is "username" and "password" — but you MUST verify this against the actual
    secret value before first apply.  If the keys differ, update these variables
    in the env-level terraform.tfvars.  Do NOT hard-code different values in the
    module — keep them as variables so each env can override if needed.
  EOT
  type        = string
  default     = "username"
}

variable "db_secret_password_key" {
  description = <<-EOT
    JSON key name for the database password inside the db_secret_arn secret.
    See db_secret_username_key for the verification note.
  EOT
  type        = string
  default     = "password"
}

# ============================================================================
# S3
# ============================================================================

variable "images_s3_bucket" {
  description = "Name of the S3 bucket used for plant images"
  type        = string
}

# ============================================================================
# Application runtime
# ============================================================================

variable "cors_origins" {
  description = "Comma-separated list of allowed CORS origins"
  type        = string
}

# ============================================================================
# Observability
# ============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# ============================================================================
# Route53 (optional)
# ============================================================================

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the DNS record"
  type        = string
  default     = ""
}

variable "route53_record_enabled" {
  description = "Whether to create a Route53 A-alias record pointing to the ALB"
  type        = bool
  default     = false
}

variable "route53_record_name" {
  description = "DNS record name to create (e.g. plant-api-staging.echocommunity.org)"
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "DNS name of the shared ALB (used for Route53 alias)"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the shared ALB (used for Route53 alias)"
  type        = string
  default     = ""
}
