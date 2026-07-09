terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "echo-plant-api-terraform-state-382724554857"
    key          = "envs/production/terraform.tfstate"
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
  env            = "production"
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
  database_name          = var.database_name

  # S3
  images_s3_bucket = var.images_s3_bucket

  # Application
  cors_origins = var.cors_origins

  # Observability
  log_retention_days = var.log_retention_days

  # Route53 — production record already exists; do NOT manage it here
  route53_record_enabled = var.route53_record_enabled
}
