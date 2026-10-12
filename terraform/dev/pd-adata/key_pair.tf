# ---------------------------------------------------------------------------
# Key pair criada nesta execucao (conta AWS nova, sem key pair previa).
#
# A chave privada e salva localmente (gitignored - ver terraform/.gitignore,
# padrao *.pem) e tambem fica no state (nao versionado). Depois do apply,
# copie o .pem para o mesmo lugar/padrao das outras chaves do repo
# (ex. ~/carrier_23092026.pem) e ajuste a permissao:
#
#   chmod 600 carrier_23092026.pem
# ---------------------------------------------------------------------------
resource "tls_private_key" "carrier" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "carrier" {
  key_name   = var.key_name
  public_key = tls_private_key.carrier.public_key_openssh

  tags = local.common_tags
}

resource "local_sensitive_file" "carrier_pem" {
  content         = tls_private_key.carrier.private_key_pem
  filename        = "${path.module}/${var.key_name}.pem"
  file_permission = "0600"
}
