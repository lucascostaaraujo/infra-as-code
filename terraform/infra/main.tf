locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "cais-infra"
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
