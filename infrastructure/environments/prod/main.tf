# =============================================================================
# Production Environment - Main Configuration
# Orchestrates all infrastructure modules
# =============================================================================

# Networking Module
module "networking" {
  source = "../../modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  container_port       = var.container_port
}

# ECR Module
module "ecr" {
  source = "../../modules/ecr"

  project_name         = var.project_name
  environment          = var.environment
  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

# ALB Module
# Creates: ALB, Target Group V1, Listener
# Also contains commented V2 target group and listener rule (see modules/alb/main.tf)
module "alb" {
  source = "../../modules/alb"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
  container_port        = var.container_port
}

# ECS Module
module "ecs" {
  source = "../../modules/ecs"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  ecs_security_group_id     = module.networking.ecs_security_group_id
  container_image           = "${module.ecr.repository_url}:latest"
  container_name            = "api"
  container_port            = var.container_port
  task_execution_role_arn   = module.iam.task_execution_role_arn
  task_role_arn             = module.iam.task_role_arn
  target_group_arn          = module.alb.target_group_arn
  desired_count             = var.desired_count
  task_cpu                  = var.task_cpu
  task_memory               = var.task_memory
}
