# ---------------------------------------------------------------------------
# ALB - 80/443 a partir de
# var.alb_allowed_cidr_blocks.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb"
  description = "cais-infra ALB - entrada HTTP/HTTPS"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.alb_allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.alb_allowed_cidr_blocks
  }

  egress {
    description = "Todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-alb-sg"
  })
}

# ---------------------------------------------------------------------------
# Tasks ECS - entrada somente do ALB (8080 Keycloak e Gatus); saida livre.
# ---------------------------------------------------------------------------
resource "aws_security_group" "ecs" {
  name        = "${var.cluster_name}-ecs-tasks"
  description = "cais-infra tasks ECS - entrada somente do ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Keycloak e Gatus (8080) a partir do ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ecs-sg"
  })
}

# ---------------------------------------------------------------------------
# RDS - Postgres (5432) a partir das tasks ECS, mais os IPs em
# var.db_allowed_cidr_blocks (acesso direto via PGAdmin/psql).
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name = "${var.cluster_name}-${var.db_identifier}-rds"
  # ATENCAO: "description" e ForceNew no provider AWS - nao mude enquanto o SG
  # estiver anexado ao RDS.
  description = "postgresinfracais RDS - inbound 5432 das tasks ECS"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Postgres a partir das tasks ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
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
