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

variable "database_name" {
  description = "Database name (non-secret)"
  type        = string
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

variable "container_env_overrides" {
  description = "Additional environment variables to inject into the container (map of name -> value)"
  type        = map(string)
  default     = {}
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
