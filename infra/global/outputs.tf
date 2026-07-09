output "ecr_repository_url" {
  description = "ECR repository URL for the plant-api image"
  value       = aws_ecr_repository.plant_api.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.plant_api.arn
}

output "gha_deploy_role_arn" {
  description = "ARN of the GitHub Actions deploy IAM role"
  value       = aws_iam_role.gha_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (data-sourced)"
  value       = data.aws_iam_openid_connect_provider.github.arn
}
