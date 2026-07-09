variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_account_id" {
  type    = string
  default = "382724554857"
}

variable "image" {
  description = "Full ECR image URI including tag"
  type        = string
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "alb_listener_arn" {
  type = string
}

variable "host_headers" {
  type = list(string)
}

variable "listener_rule_priority" {
  type = number
}

variable "rds_security_group_ids" {
  type = list(string)
}

variable "database_host" {
  type = string
}

variable "database_port" {
  type    = number
  default = 5432
}

variable "database_name" {
  type = string
}

variable "images_s3_bucket" {
  type = string
}

variable "cors_origins" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "route53_record_enabled" {
  type    = bool
  default = false
}
