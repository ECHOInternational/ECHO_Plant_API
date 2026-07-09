terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  name_prefix = "plant-api-${var.env}"

  # Base environment variables (non-secret).
  # DATABASE_NAME is intentionally omitted: config/database.yml already
  # hardcodes the database name per RAILS_ENV (Plant_API_production /
  # Plant_API_staging), so injecting it as an env var is redundant and
  # could cause confusion if the two values diverge.
  base_env = [
    { name = "RAILS_ENV", value = var.env == "staging" ? "staging" : "production" },
    { name = "RACK_ENV", value = var.env == "staging" ? "staging" : "production" },
    { name = "RAILS_LOG_TO_STDOUT", value = "true" },
    { name = "RAILS_MAX_THREADS", value = "5" },
    { name = "RAILS_SERVE_STATIC_FILES", value = "false" },
    { name = "PORT", value = "3000" },
    { name = "LOG_LEVEL", value = "info" },
    { name = "WEB_CONCURRENCY", value = "2" },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "IMAGES_S3_BUCKET", value = var.images_s3_bucket },
    { name = "CORS_ORIGINS", value = var.cors_origins },
    { name = "APPLICATION_JWT_ALGORITHM", value = "RS256" },
    { name = "DATABASE_HOST", value = var.database_host },
    { name = "DATABASE_PORT", value = tostring(var.database_port) },
  ]

  # Override env vars merged on top of base
  merged_env_map        = merge({ for e in local.base_env : e.name => e.value }, var.container_env_overrides)
  container_environment = [for k, v in local.merged_env_map : { name = k, value = v }]

  # -------------------------------------------------------------------------
  # Secrets Manager ARNs for the task secrets block.
  #
  # DATABASE_USERNAME / DATABASE_PASSWORD come from the per-app scoped secret
  # in the rds/echocommunity-production/ prefix.  The JSON key names inside
  # those secrets follow the house convention ("username" / "password") but
  # MUST be verified against the actual secret value before first apply —
  # see infra/README.md §Secrets.
  #
  # APPLICATION_JWT_SECRET is a dedicated per-env plain-string secret
  # (plant-api-<env>/application-jwt-secret).  It is referenced as a
  # whole-value (no JSON key selector).
  # -------------------------------------------------------------------------

  db_secret_arn  = var.db_secret_arn
  jwt_secret_arn = aws_secretsmanager_secret.jwt.arn

  task_secrets = [
    {
      name      = "DATABASE_USERNAME"
      valueFrom = "${local.db_secret_arn}:${var.db_secret_username_key}::"
    },
    {
      name      = "DATABASE_PASSWORD"
      valueFrom = "${local.db_secret_arn}:${var.db_secret_password_key}::"
    },
    {
      name      = "APPLICATION_JWT_SECRET"
      valueFrom = local.jwt_secret_arn
    },
  ]

  # Execution role needs GetSecretValue on both secrets.
  execution_secret_arns = [
    local.db_secret_arn,
    local.jwt_secret_arn,
  ]
}

# ============================================================================
# ECS Cluster
# ============================================================================

resource "aws_ecs_cluster" "main" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

# ============================================================================
# Secrets Manager — APPLICATION_JWT_SECRET (per-env, per-app copy)
#
# Terraform creates the secret shell with a placeholder value.
# The real RSA public key must be seeded out-of-band before first deploy
# (see infra/README.md §Secrets).  lifecycle.ignore_changes ensures
# Terraform never overwrites the real value after seeding.
#
# For production: seed from the current EB APPLICATION_JWT_SECRET env var.
# For staging:    copy from echo-seeds-staging/application-jwt-secret
#                 (see README for the exact pipe command).
# ============================================================================

resource "aws_secretsmanager_secret" "jwt" {
  name        = "plant-api-${var.env}/application-jwt-secret"
  description = "ECHOcommunity RS256 public key body, verifies access tokens (${var.env})"

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_placeholder" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = "PLACEHOLDER_CHANGE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ============================================================================
# IAM — Execution Role (pull images, write logs, read Secrets Manager)
# ============================================================================

data "aws_iam_policy_document" "execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json
  description        = "ECS task execution role for ${local.name_prefix}"

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "execution_ecr_logs" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# GetSecretValue scoped to exactly the two secret ARNs used by the task.
# No kms:Decrypt statement is required because all referenced secrets use
# the AWS-managed default key (KmsKeyId = null, verified via DescribeSecret).
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid    = "SecretsManagerGetValue"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = local.execution_secret_arns
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "secretsmanager-read-${local.name_prefix}"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# ============================================================================
# IAM — Task Role (S3 images access)
# ============================================================================

data "aws_iam_policy_document" "task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json
  description        = "ECS task role for ${local.name_prefix} (S3 images)"

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "task_s3" {
  statement {
    sid    = "ImagesS3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.images_s3_bucket}",
      "arn:aws:s3:::${var.images_s3_bucket}/*",
    ]
  }
}

resource "aws_iam_role_policy" "task_s3" {
  name   = "s3-images-${local.name_prefix}"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_s3.json
}

# ============================================================================
# Security Group — ECS Tasks
# ============================================================================

resource "aws_security_group" "tasks" {
  name        = "${local.name_prefix}-tasks"
  description = "Plant API ${var.env} ECS tasks — ingress from ALB only"
  vpc_id      = var.vpc_id

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${local.name_prefix}-tasks"
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "Allow port 3000 from the shared ALB"
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.alb_security_group_id
}

# Allow tasks SG to reach each RDS security group on port 5432
# Note: we add an INGRESS rule TO each RDS SG, not to the tasks SG.
resource "aws_vpc_security_group_ingress_rule" "rds_from_tasks" {
  for_each = toset(var.rds_security_group_ids)

  security_group_id            = each.value
  description                  = "Allow port 5432 from ${local.name_prefix} ECS tasks"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.tasks.id
}

# ============================================================================
# ECS Task Definition — application (web)
# ============================================================================

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name_prefix}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = var.image
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = local.container_environment

      secrets = local.task_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

# ============================================================================
# ECS Task Definition — one-off DB migration
# ============================================================================

resource "aws_ecs_task_definition" "migrate" {
  family                   = "${local.name_prefix}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "migrate"
      image     = var.image
      essential = true
      command   = ["bundle", "exec", "rails", "db:migrate"]

      environment = local.container_environment

      secrets = local.task_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "migrate"
        }
      }
    }
  ])

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

# ============================================================================
# ALB Target Group
# ============================================================================

resource "aws_lb_target_group" "web" {
  name        = "${local.name_prefix}-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# ALB Listener Rule
# ============================================================================

resource "aws_lb_listener_rule" "web" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = var.host_headers
    }
  }

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }
}

# ============================================================================
# Route53 A-alias record (optional)
# ============================================================================

resource "aws_route53_record" "web" {
  count = var.route53_record_enabled ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.route53_record_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ============================================================================
# ECS Service
# ============================================================================

resource "aws_ecs_service" "web" {
  name            = "${local.name_prefix}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  tags = {
    Project   = "plant-api"
    Env       = var.env
    ManagedBy = "terraform"
  }

  depends_on = [
    aws_lb_listener_rule.web,
    aws_iam_role_policy_attachment.execution_ecr_logs,
  ]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# ============================================================================
# Auto Scaling
# ============================================================================

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${local.name_prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
