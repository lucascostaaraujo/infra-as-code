# ---------------------------------------------------------------------------
# Repositorios ECR - pd-adata-front / pd-adata-back
# Tag mutability: Mutable | Scan on push | Encryption: AES-256 (SSE-S3, chave
# gerenciada pela AWS - nao KMS)
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "pd_adata" {
  for_each = var.ecr_repository_names

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Lifecycle policy (identica nos dois repositorios):
#   1. Remove Untagged Images        -> untagged, >1 dia desde o push
#   2. Remove old dev images         -> tag prefixo "dev-",   > 2 imagens
#   3. Remove old homol images       -> tag prefixo "homol-", > 2 imagens
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "pd_adata" {
  for_each = aws_ecr_repository.pd_adata

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove Untagged Images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove old dev images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 2
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Remove old homol images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["homol-"]
          countType     = "imageCountMoreThan"
          countNumber   = 2
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
