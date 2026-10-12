# ---------------------------------------------------------------------------
# Security group da EC2 - sem inbound (acesso exclusivamente via SSM).
# Portas web, se forem necessarias no futuro, devem ser abertas manualmente
# (ou via ajuste explicito deste recurso).
# ---------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.vpc_name}-pd-adata-ec2"
  description = "P&D-Adata EC2 - sem inbound (acesso via SSM); todo trafego de saida liberado"
  vpc_id      = aws_vpc.carrier.id

  egress {
    description = "Todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name} - sg"
  })
}

# ---------------------------------------------------------------------------
# Security group do RDS - Postgres (5432) a partir da EC2 do P&D-Adata, mais
# os IPs em var.db_allowed_cidr_blocks (acesso direto via PGAdmin/psql local -
# vazio por padrao, so libera o que for explicitamente adicionado).
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name = "${var.vpc_name}-postgrescarrier-rds"
  # ATENCAO: "description" e ForceNew no provider AWS (nao pode ser atualizado
  # in-place, so recriando o SG). Nao mude este texto enquanto o SG estiver
  # anexado a um RDS ativo - a AWS bloqueia o detach direto da ENI gerenciada
  # pelo servico RDS (so o proprio RDS pode fazer isso via ModifyDBInstance).
  description = "postgrescarrier RDS - inbound 5432 somente da EC2 do P&D-Adata"
  vpc_id      = aws_vpc.carrier.id

  ingress {
    description     = "Postgres a partir da EC2 do P&D-Adata"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  dynamic "ingress" {
    for_each = length(var.db_allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Postgres a partir de IPs liberados manualmente (PGAdmin/psql)"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.db_allowed_cidr_blocks
    }
  }

  egress {
    description = "Todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.db_identifier} - sg"
  })
}
