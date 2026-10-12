# ---------------------------------------------------------------------------
# Cluster ECS "cais-infra" - Fargate On-Demand (sem Fargate Spot).
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# Sem CloudWatch Logs de proposito (logs/metricas serao tratados por outra
# ferramenta no futuro): as task definitions nao tem logConfiguration.

# ---------------------------------------------------------------------------
# Keycloak - 2 vCPU / 4GB
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "keycloak" {
  family                   = "${var.cluster_name}-keycloak"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.keycloak.cpu
  memory                   = var.keycloak.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_gib > 20 ? [1] : []
    content {
      size_in_gib = var.ephemeral_storage_gib
    }
  }

  container_definitions = jsonencode([
    {
      name      = "keycloak"
      image     = var.keycloak.image
      essential = true
      command   = ["start"]

      portMappings = [{ containerPort = 8080, protocol = "tcp" }]

      environment = [
        { name = "KC_DB", value = "postgres" },
        { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_db_instance.this.address}:5432/${var.db_name}" },
        { name = "KC_DB_USERNAME", value = var.db_username },
        { name = "KC_BOOTSTRAP_ADMIN_USERNAME", value = var.keycloak_admin_username },
        # TLS termina no ALB
        { name = "KC_HTTP_ENABLED", value = "true" },
        { name = "KC_PROXY_HEADERS", value = "xforwarded" },
        { name = "KC_HOSTNAME", value = "${local.scheme}://${var.keycloak_hostname}" },
        { name = "KC_HOSTNAME_STRICT", value = "false" },
        { name = "KC_HEALTH_ENABLED", value = "true" },
      ]

      secrets = [
        { name = "KC_DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "KC_BOOTSTRAP_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.keycloak_admin_password.arn },
      ]
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "keycloak" {
  name            = "keycloak"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = var.keycloak.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  # Keycloak leva alguns minutos no primeiro boot (build + migracao do schema)
  health_check_grace_period_seconds = 300

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak.arn
    container_name   = "keycloak"
    container_port   = 8080
  }

  depends_on = [
    aws_ecs_cluster_capacity_providers.this,
    aws_lb_listener_rule.keycloak,
  ]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Gatus - 1 vCPU / 2GB
#
# A imagem do Gatus e "scratch" (sem shell) e o Fargate nao tem bind mount de
# arquivo, entao um container init (aws-cli) baixa o config.yaml do S3
# (s3://<bucket>/gatus/config.yaml, editavel pelo console) para um volume
# compartilhado antes do Gatus subir. Para aplicar uma mudanca no arquivo:
# ECS > servico gatus > Update service > Force new deployment.
# O Terraform so semeia o arquivo inicial (ver s3.tf) e nao o sobrescreve.
# ---------------------------------------------------------------------------
locals {
  gatus_default_config = <<-EOT
    web:
      port: 8080
    endpoints:
      - name: keycloak
        url: "${local.scheme}://${var.keycloak_hostname}/realms/master"
        interval: 1m
        conditions:
          - "[STATUS] == 200"
          - "[RESPONSE_TIME] < 2000"
  EOT

  gatus_config = coalesce(var.gatus_config, local.gatus_default_config)
}

resource "aws_ecs_task_definition" "gatus" {
  family                   = "${var.cluster_name}-gatus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.gatus.cpu
  memory                   = var.gatus.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.gatus_task.arn

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_gib > 20 ? [1] : []
    content {
      size_in_gib = var.ephemeral_storage_gib
    }
  }

  volume {
    name = "config"
  }

  container_definitions = jsonencode([
    {
      name      = "gatus-config"
      image     = "public.ecr.aws/aws-cli/aws-cli:latest"
      essential = false
      # entrypoint da imagem ja e "aws"
      command = ["s3", "cp", "s3://${aws_s3_bucket.infra.id}/${local.gatus_config_key}", "/config/config.yaml"]

      environment = [
        { name = "AWS_DEFAULT_REGION", value = var.region },
      ]

      mountPoints = [{ sourceVolume = "config", containerPath = "/config" }]
    },
    {
      name      = "gatus"
      image     = var.gatus.image
      essential = true

      portMappings = [{ containerPort = 8080, protocol = "tcp" }]

      environment = [
        { name = "GATUS_CONFIG_PATH", value = "/config/config.yaml" },
      ]

      mountPoints = [{ sourceVolume = "config", containerPath = "/config" }]

      dependsOn = [{ containerName = "gatus-config", condition = "SUCCESS" }]
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "gatus" {
  name            = "gatus"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.gatus.arn
  desired_count   = var.gatus.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gatus.arn
    container_name   = "gatus"
    container_port   = 8080
  }

  depends_on = [
    aws_ecs_cluster_capacity_providers.this,
    aws_lb_listener_rule.gatus,
  ]

  tags = local.common_tags
}
