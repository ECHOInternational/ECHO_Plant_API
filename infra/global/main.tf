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
    key          = "global/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# ECR Repository
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "plant_api" {
  name                 = "plant-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project   = "plant-api"
    ManagedBy = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "plant_api" {
  repository = aws_ecr_repository.plant_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 25 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "main-", "master-"]
          countType     = "imageCountMoreThan"
          countNumber   = 25
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC — data-source the existing provider (do not recreate)
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# IAM Role: gha-plant-api-deploy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "gha_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:ECHOInternational/ECHO_Plant_API:ref:refs/heads/master",
        "repo:ECHOInternational/ECHO_Plant_API:environment:staging",
        "repo:ECHOInternational/ECHO_Plant_API:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "gha_deploy" {
  name               = "gha-plant-api-deploy"
  assume_role_policy = data.aws_iam_policy_document.gha_assume_role.json
  description        = "Assumed by GitHub Actions to build/push images and deploy to ECS"

  tags = {
    Project   = "plant-api"
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Inline policy for the deploy role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "gha_deploy_policy" {
  # ECR authentication (account-level; no resource restriction possible)
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  # ECR push scoped to the plant-api repository only
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.plant_api.arn]
  }

  # ECS: register task definitions, describe services, update services, run tasks
  # Scoped to the two Plant API clusters
  statement {
    sid    = "ECSManage"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:RunTask",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values = [
        "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:cluster/plant-api-staging",
        "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:cluster/plant-api-production",
      ]
    }
  }

  # iam:PassRole scoped to the task and execution roles for both environments
  statement {
    sid    = "PassTaskRoles"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/plant-api-*-task-role",
      "arn:aws:iam::${var.aws_account_id}:role/plant-api-*-execution-role",
    ]
  }

  # CloudWatch Logs read (for deployment verification)
  statement {
    sid    = "LogsRead"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/ecs/plant-api-*",
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/ecs/plant-api-*:*",
    ]
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "gha-plant-api-deploy-policy"
  role   = aws_iam_role.gha_deploy.id
  policy = data.aws_iam_policy_document.gha_deploy_policy.json
}
