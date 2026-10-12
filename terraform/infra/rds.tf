# ---------------------------------------------------------------------------
# RDS Postgres "postgresinfracais" - instancia nova (sem snapshot), mesmo
# padrao de dev/pd-adata/rds_postgresadata.tf. O database var.db_name
# ("keycloak") ja e criado na instancia.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.vpc_name}-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = local.common_tags
}

resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "this" {
  identifier     = var.db_identifier
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true

  multi_az = false

  license_model                       = "postgresql-license"
  iam_database_authentication_enabled = false
  storage_encrypted                   = false

  auto_minor_version_upgrade = true

  backup_retention_period = var.db_backup_retention_period
  backup_window           = var.db_backup_window
  backup_target           = "region"
  copy_tags_to_snapshot   = true

  # Enhanced Monitoring desligado (monitoring_interval = 0): nao publica no
  # CloudWatch. Performance Insights tambem fica desligado.
  monitoring_interval          = var.db_monitoring_interval
  performance_insights_enabled = false
  database_insights_mode       = "standard"

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.db_identifier}-final-snapshot"

  apply_immediately = false

  tags = merge(local.common_tags, {
    Name = var.db_identifier
  })

  lifecycle {
    # Minor upgrades automaticos mudam engine_version em relacao ao "17" declarado.
    ignore_changes = [engine_version]
  }
}
