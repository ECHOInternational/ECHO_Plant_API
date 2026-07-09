terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "echo-terraform-state-382724554857"
    key          = "plant-api/staging.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "plant_api" {
  source = "../../modules/plant-api"

  # Core
  env            = "staging"
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  # Container image (updated by CI/CD pipeline)
  image = var.image

  # ECS sizing
  cpu           = var.cpu
  memory        = var.memory
  desired_count = var.desired_count
  min_capacity  = var.min_capacity
  max_capacity  = var.max_capacity

  # Networking
  vpc_id                 = var.vpc_id
  subnet_ids             = var.subnet_ids
  alb_security_group_id  = var.alb_security_group_id
  alb_listener_arn       = var.alb_listener_arn
  host_headers           = var.host_headers
  listener_rule_priority = var.listener_rule_priority

  # RDS
  rds_security_group_ids = var.rds_security_group_ids
  database_host          = var.database_host
  database_port          = var.database_port

  # Secrets Manager — DB credentials
  db_secret_arn          = var.db_secret_arn
  db_secret_username_key = var.db_secret_username_key
  db_secret_password_key = var.db_secret_password_key

  # S3
  images_s3_bucket = var.images_s3_bucket

  # Application
  cors_origins = var.cors_origins

  # Observability
  log_retention_days = var.log_retention_days

  # Route53 — staging record is managed here
  route53_record_enabled = var.route53_record_enabled
  route53_zone_id        = var.route53_zone_id
  route53_record_name    = var.route53_record_name
  alb_dns_name           = var.alb_dns_name
  alb_zone_id            = var.alb_zone_id
}
