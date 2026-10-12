# ---------------------------------------------------------------------------
# Certificado ACM para auth/gatus.institutocais.org.br. O DNS fica no
# Registro.br (nao no Route 53), entao a validacao e manual: crie os CNAMEs do
# output acm_validation_records la. Sem aws_acm_certificate_validation de
# proposito - ele travaria o apply esperando o DNS. Depois que o certificado
# estiver ISSUED, rode de novo com enable_https = true.
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "this" {
  domain_name       = var.keycloak_hostname
  validation_method = "DNS"

  subject_alternative_names = [var.gatus_hostname]

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}
