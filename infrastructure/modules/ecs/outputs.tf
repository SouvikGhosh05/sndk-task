# =============================================================================
# ECS Module Outputs
# =============================================================================

output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "service_id" {
  description = "ECS service ID"
  value       = aws_ecs_service.main.id
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.main.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}

# =============================================================================
# OPTIONAL: Outputs for V2 Service (uncomment when using V2)
# =============================================================================

# output "service_v2_id" {
#   description = "ECS service V2 ID"
#   value       = aws_ecs_service.v2.id
# }
#
# output "service_v2_name" {
#   description = "ECS service V2 name"
#   value       = aws_ecs_service.v2.name
# }
#
# output "task_definition_v2_arn" {
#   description = "ECS task definition V2 ARN"
#   value       = aws_ecs_task_definition.v2.arn
# }
#
# output "log_group_v2_name" {
#   description = "CloudWatch log group V2 name"
#   value       = aws_cloudwatch_log_group.v2.name
# }
