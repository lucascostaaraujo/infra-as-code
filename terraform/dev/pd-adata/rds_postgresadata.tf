# ---------------------------------------------------------------------------
# postgresadata - segunda instancia RDS Postgres, restaurada a partir de um
# snapshot EXISTENTE da postgrescarrier (automatico, gerado pelo backup diario
# - prefixo "rds:"). Instancia nova e independente: depois de criada, nao tem
# mais nenhuma ligacao viva com a postgrescarrier (os dados divergem a partir
# da data do snapshot).
#
# Usa var.db2_snapshot_identifier em vez de um aws_db_snapshot gerenciado pelo
# Terraform porque a postgrescarrier estava parada (autoOnOff) no momento da
# criacao, impedindo tirar um snapshot novo na hora. Snapshots automaticos sao
# purgados pela AWS conforme a retencao (db_backup_retention_period, 7 dias) -
# isso so importa na criacao (gracas ao lifecycle.ignore_changes abaixo), mas
# se for recriar a instancia do zero depois que esse snapshot expirar, aponte
# para um snapshot mais recente.
# ---------------------------------------------------------------------------

# Senha do master user da postgresadata - independente da senha da
# postgrescarrier (cada instancia com sua propria credencial).
resource "random_password" "postgresadata" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "postgresadata" {
  identifier     = var.db2_identifier
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db2_instance_class

  # Restaura a partir do snapshot existente (var.db2_snapshot_identifier).
  # Engine/storage/dados vem do snapshot; so username/password sao
  # sobrescritos (ModifyDBInstance pos-restore) para dar uma credencial
  # propria a esta instancia.
  snapshot_identifier = var.db2_snapshot_identifier
  password            = random_password.postgresadata.result

  storage_type = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.carrier.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true

  multi_az = false

  license_model                       = "postgresql-license"
  engine_lifecycle_support            = "open-source-rds-extended-support"
  iam_database_authentication_enabled = false
  storage_encrypted                   = false

  auto_minor_version_upgrade = true

  backup_retention_period = var.db_backup_retention_period
  backup_window           = var.db_backup_window
  backup_target           = "region"
  copy_tags_to_snapshot   = true

  monitoring_interval    = var.db_monitoring_interval
  monitoring_role_arn    = aws_iam_role.rds_monitoring.arn
  database_insights_mode = "standard"

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.db2_identifier}-final-snapshot"

  apply_immediately = false

  # autoOnOff=true -> gerenciada pela Lambda de liga/desliga (ver autooff.tf).
  # Remova a tag se quiser que esta instancia fique sempre ligada.
  tags = merge(local.common_tags, {
    Name      = var.db2_identifier
    autoOnOff = "true"
  })

  lifecycle {
    # snapshot_identifier so importa no momento da criacao (restore); nao faz
    # sentido o Terraform tentar "re-restaurar" a instancia em runs futuros.
    ignore_changes = [snapshot_identifier]
  }
}
