output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.web.name
}

output "task_definition_arn" {
  description = "Latest web task definition ARN"
  value       = aws_ecs_task_definition.web.arn
}

output "migrate_task_definition_arn" {
  description = "Latest migration task definition ARN"
  value       = aws_ecs_task_definition.migrate.arn
}

output "target_group_arn" {
  description = "ALB target group ARN"
  value       = aws_lb_target_group.web.arn
}

output "tasks_security_group_id" {
  description = "Security group ID attached to ECS tasks"
  value       = aws_security_group.tasks.id
}

output "execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "ssm_parameter_prefix" {
  description = "SSM parameter path prefix for secrets"
  value       = local.ssm_prefix
}
