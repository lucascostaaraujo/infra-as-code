# ---------------------------------------------------------------------------
# Buckets S3 (general purpose) - pd-adata-anexos-dev / pd-adata-rda-dev / pd-adata-temp-dev
#
# Todas as opcoes abaixo replicam a config pedida. Itens que ja sao o default
# da AWS para um bucket novo (versioning Disabled, MFA delete Disabled,
# access logging Disabled, EventBridge Off, transfer acceleration Disabled,
# Object Lock Disabled, requester pays Disabled, static website Disabled) NAO
# tem recurso proprio: nao criar o recurso equivalente = permanece no default,
# ja que a API do S3 nao aceita "Disabled" como valor setavel para a maioria
# dessas configuracoes (so Enabled/Suspended, uma vez habilitado).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "pd_adata" {
  for_each = var.s3_bucket_names

  bucket = each.value

  tags = local.common_tags
}

# Encryption type: SSE-S3 (AES-256) | Bucket Key: Disabled
resource "aws_s3_bucket_server_side_encryption_configuration" "pd_adata" {
  for_each = aws_s3_bucket.pd_adata

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# Block all public access: On
resource "aws_s3_bucket_public_access_block" "pd_adata" {
  for_each = aws_s3_bucket.pd_adata

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Blocked encryption types: SSE-C. Nao existe um argumento dedicado no
# provider AWS para isso; a forma padrao de bloquear SSE-C e negar via bucket
# policy qualquer PutObject que traga o header de SSE-C.
resource "aws_s3_bucket_policy" "pd_adata_block_ssec" {
  for_each = aws_s3_bucket.pd_adata

  bucket = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenySSECUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${each.value.arn}/*"
        Condition = {
          "Null" = {
            "s3:x-amz-server-side-encryption-customer-algorithm" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.pd_adata]
}
