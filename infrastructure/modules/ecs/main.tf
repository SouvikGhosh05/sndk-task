# =============================================================================
# ECS Module - Cluster, Task Definition, Service
# =============================================================================

# Data source for current region
data "aws_region" "current" {}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-${var.environment}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "NODE_ENV"
        value = "production"
      },
      {
        name  = "PORT"
        value = tostring(var.container_port)
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.id
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.container_port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name = "${var.project_name}-${var.environment}-task"
  }
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  depends_on = [aws_ecs_task_definition.main]

  tags = {
    Name = "${var.project_name}-${var.environment}-service"
  }
}

# =============================================================================
# OPTIONAL: Second ECS Service (V2) for Blue/Green Deployment
# =============================================================================
# Uncomment to deploy a second service alongside V1
# Prerequisites:
#   1. Uncomment V2 resources in modules/alb/main.tf (Target Group + Listener Rule)
#   2. Uncomment V2 outputs in modules/alb/outputs.tf
#   3. Add target_group_v2_arn variable to this module
#   4. Uncomment resources below
# Traffic: ALB routes /v2/* to this service
# =============================================================================

# CloudWatch Log Group V2
resource "aws_cloudwatch_log_group" "v2" {
  name              = "/ecs/${var.project_name}-${var.environment}-v2"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-logs-v2"
  }
}

# ECS Task Definition V2
resource "aws_ecs_task_definition" "v2" {
  family                   = "${var.project_name}-${var.environment}-task-v2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([{
    name      = "${var.container_name}-v2"
    image     = replace(var.container_image, ":latest", ":v2.0.0")  # Use v2 tag
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "NODE_ENV"
        value = "production"
      },
      {
        name  = "PORT"
        value = tostring(var.container_port)
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.id
      },
      {
        name  = "VERSION"
        value = "v2.0.0"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.v2.name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.container_port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name = "${var.project_name}-${var.environment}-task-v2"
  }
}

# ECS Service V2 - Runs in Same Cluster
resource "aws_ecs_service" "v2" {
  name            = "${var.project_name}-${var.environment}-service-v2"
  cluster         = aws_ecs_cluster.main.id  # Reuses V1 cluster
  task_definition = aws_ecs_task_definition.v2.arn
  desired_count   = var.desired_count  # Same as V1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids  # Same as V1
    security_groups  = [var.ecs_security_group_id]  # Same as V1
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_v2_arn  # New variable needed
    container_name   = "${var.container_name}-v2"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  depends_on = [aws_ecs_task_definition.v2]

  tags = {
    Name = "${var.project_name}-${var.environment}-service-v2"
  }
}
