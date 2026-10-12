# ---------------------------------------------------------------------------
# Bucket "infra-cais" - guarda configuracoes editaveis pelo console do S3.
#   gatus/config.yaml -> config do Gatus (baixado pelo container init a cada
#                        start da task)
# ---------------------------------------------------------------------------
locals {
  gatus_config_key = "gatus/config.yaml"
}

resource "aws_s3_bucket" "infra" {
  bucket = var.s3_bucket_name

  tags = merge(local.common_tags, {
    Name = var.s3_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "infra" {
  bucket = aws_s3_bucket.infra.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "infra" {
  bucket = aws_s3_bucket.infra.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versionamento: permite voltar a versao anterior do config se uma edicao
# quebrar o Gatus (console S3 > objeto > Versions).
resource "aws_s3_bucket_versioning" "infra" {
  bucket = aws_s3_bucket.infra.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Semente do config do Gatus. ignore_changes = all: depois de criado, o
# conteudo e gerenciado pelo console do S3 e o Terraform nunca o sobrescreve.
resource "aws_s3_object" "gatus_config" {
  bucket       = aws_s3_bucket.infra.id
  key          = local.gatus_config_key
  content      = local.gatus_config
  content_type = "application/x-yaml"

  tags = local.common_tags

  lifecycle {
    ignore_changes = all
  }

  depends_on = [aws_s3_bucket_versioning.infra]
}

# ---------------------------------------------------------------------------
# Task role do Gatus - somente leitura de gatus/* no bucket.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "gatus_task" {
  name               = "${var.cluster_name}-gatus-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "gatus_task_s3" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.infra.arn}/gatus/*"]
  }
}

resource "aws_iam_role_policy" "gatus_task_s3" {
  name   = "read-gatus-config"
  role   = aws_iam_role.gatus_task.id
  policy = data.aws_iam_policy_document.gatus_task_s3.json
}
