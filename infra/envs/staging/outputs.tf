output "cluster_name" {
  value = module.plant_api.cluster_name
}

output "service_name" {
  value = module.plant_api.service_name
}

output "target_group_arn" {
  value = module.plant_api.target_group_arn
}

output "tasks_security_group_id" {
  value = module.plant_api.tasks_security_group_id
}

output "log_group_name" {
  value = module.plant_api.log_group_name
}

output "jwt_secret_arn" {
  description = "ARN of plant-api-staging/application-jwt-secret — seed this before first deploy"
  value       = module.plant_api.jwt_secret_arn
}

output "migrate_task_definition_arn" {
  value = module.plant_api.migrate_task_definition_arn
}
