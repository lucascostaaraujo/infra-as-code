# ---------------------------------------------------------------------------
# DB Subnet Group - precisa de subnets em >= 2 AZs mesmo para instancia
# Single-AZ (exigencia da AWS). Compartilhado entre todas as instancias RDS
# do stack (postgresadata, em rds_postgresadata.tf, tambem usa este recurso).
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "carrier" {
  name       = "${var.vpc_name}-db-subnet-group"
  subnet_ids = [aws_subnet.primary.id, aws_subnet.secondary.id]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# A instancia RDS "postgrescarrier" que vivia aqui foi excluida (substituida
# pela "postgresadata", restaurada de um snapshot dela - ver
# rds_postgresadata.tf). O security group (aws_security_group.rds, em
# security_groups.tf) e a role de Enhanced Monitoring (aws_iam_role.rds_monitoring,
# em iam.tf) continuam existindo porque sao compartilhados com a postgresadata.
# ---------------------------------------------------------------------------
