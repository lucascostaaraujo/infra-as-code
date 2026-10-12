# ---------------------------------------------------------------------------
# Segredos (Secrets Manager), injetados nas tasks pelo ECS. Nada de senha em
# texto puro na task definition.
# ---------------------------------------------------------------------------

resource "random_password" "keycloak_admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.cluster_name}/${var.db_identifier}/master-password"
  description             = "Senha do master user do RDS ${var.db_identifier} (usada pelo Keycloak)"
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_secretsmanager_secret" "keycloak_admin_password" {
  name                    = "${var.cluster_name}/keycloak/admin-password"
  description             = "Senha do admin inicial (bootstrap) do Keycloak"
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "keycloak_admin_password" {
  secret_id     = aws_secretsmanager_secret.keycloak_admin_password.id
  secret_string = random_password.keycloak_admin.result
}

# ---------------------------------------------------------------------------
# Task execution role - puxa imagem, escreve logs e le os segredos acima.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.cluster_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.db_password.arn,
      aws_secretsmanager_secret.keycloak_admin_password.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}
