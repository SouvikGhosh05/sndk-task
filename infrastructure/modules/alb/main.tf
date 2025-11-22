# =============================================================================
# ALB Module - Application Load Balancer
# =============================================================================

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # Required for Fargate

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-http-listener"
  }
}

# =============================================================================
# OPTIONAL: Additional Target Group & Listener Rule for Second Service (V2)
# =============================================================================
# Uncomment to create a second target group and path-based routing
# Allows Blue/Green deployments with same ALB
# Traffic routing: /v2/* → Target Group V2
# =============================================================================

# # Target Group V2
# resource "aws_lb_target_group" "v2" {
#   name        = "${var.project_name}-${var.environment}-tg-v2"
#   port        = var.container_port
#   protocol    = "HTTP"
#   vpc_id      = var.vpc_id
#   target_type = "ip"
#
#   health_check {
#     enabled             = true
#     healthy_threshold   = var.healthy_threshold
#     unhealthy_threshold = var.unhealthy_threshold
#     timeout             = var.health_check_timeout
#     interval            = var.health_check_interval
#     path                = var.health_check_path
#     protocol            = "HTTP"
#     matcher             = "200"
#   }
#
#   deregistration_delay = 30
#
#   tags = {
#     Name = "${var.project_name}-${var.environment}-tg-v2"
#   }
# }

# # Listener Rule for Path-Based Routing
# # Routes /v2/* traffic to Target Group V2
# resource "aws_lb_listener_rule" "v2" {
#   listener_arn = aws_lb_listener.http.arn
#   priority     = 10
#
#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.v2.arn
#   }
#
#   condition {
#     path_pattern {
#       values = ["/v2/*"]
#     }
#   }
#
#   tags = {
#     Name = "${var.project_name}-${var.environment}-rule-v2"
#   }
# }
