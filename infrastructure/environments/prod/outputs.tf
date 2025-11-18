# =============================================================================
# Production Environment Outputs
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS name - use this URL to access the application"
  value       = module.alb.alb_dns_name
}

output "application_url" {
  description = "Application URL"
  value       = "http://${module.alb.alb_dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = module.ecr.repository_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP"
  value       = module.networking.nat_gateway_public_ip
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for ECS tasks"
  value       = module.ecs.log_group_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
