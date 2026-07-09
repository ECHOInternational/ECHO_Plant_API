output "cluster_name" {
  value = module.plant_api.cluster_name
}

output "service_name" {
  value = module.plant_api.service_name
}

output "target_group_arn" {
  description = "New ECS target group ARN — used during production cutover to update rule 15"
  value       = module.plant_api.target_group_arn
}

output "tasks_security_group_id" {
  value = module.plant_api.tasks_security_group_id
}

output "log_group_name" {
  value = module.plant_api.log_group_name
}

output "ssm_parameter_prefix" {
  value = module.plant_api.ssm_parameter_prefix
}

output "migrate_task_definition_arn" {
  value = module.plant_api.migrate_task_definition_arn
}
