# =============================================================================
# ALB Module Outputs
# =============================================================================

output "alb_id" {
  description = "ALB ID"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name - use this to access the application"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Route53 zone ID"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.main.arn
}

output "target_group_name" {
  description = "Target group name"
  value       = aws_lb_target_group.main.name
}

output "listener_arn" {
  description = "HTTP listener ARN"
  value       = aws_lb_listener.http.arn
}

# =============================================================================
# OPTIONAL: Outputs for V2 Resources (uncomment when using V2)
# =============================================================================

output "target_group_v2_arn" {
  description = "Target group V2 ARN"
  value       = aws_lb_target_group.v2.arn
}

output "target_group_v2_name" {
  description = "Target group V2 name"
  value       = aws_lb_target_group.v2.name
}

output "listener_rule_v2_arn" {
  description = "Listener rule V2 ARN"
  value       = aws_lb_listener_rule.v2.arn
}
