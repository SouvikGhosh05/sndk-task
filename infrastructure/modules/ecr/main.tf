# =============================================================================
# ECR Module - Elastic Container Registry
# =============================================================================

# ECR Repository
resource "aws_ecr_repository" "main" {
  name                 = "${var.project_name}-${var.environment}-api"
  image_tag_mutability = var.image_tag_mutability

  # Enable image scanning on push (DevSecOps best practice)
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Enable encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr"
  }
}

# Lifecycle Policy - Keep only last N images
resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.image_retention_count} images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = var.image_retention_count
      }
      action = {
        type = "expire"
      }
    }]
  })
}
