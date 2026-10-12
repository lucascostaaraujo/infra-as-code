locals {
  common_tags = merge(
    {
      Name        = var.name
      Environment = var.environment
      Project     = "pmo"
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

# ---------------------------------------------------------------------------
# AMI - Ubuntu mais atual (24.04 LTS "noble", amd64), publicada pela Canonical
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---------------------------------------------------------------------------
# Security group novo: PMO_Apps (NPM / Nginx Proxy Manager)
# ---------------------------------------------------------------------------
resource "aws_security_group" "pmo_apps" {
  name        = "PMO_Apps"
  description = "PMO applications - NPM (Nginx Proxy Manager): HTTP/HTTPS e dashboard"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "PMO_Apps"
  })
}

resource "aws_vpc_security_group_ingress_rule" "pmo_apps" {
  for_each = var.pmo_apps_ingress_rules

  security_group_id = aws_security_group.pmo_apps.id
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  cidr_ipv4         = each.value.cidr_ipv4

  tags = {
    Name = each.key
  }
}

# Egress liberado (equivalente ao comportamento padrao do console EC2)
resource "aws_vpc_security_group_egress_rule" "pmo_apps_all" {
  security_group_id = aws_security_group.pmo_apps.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Elastic IP novo
# ---------------------------------------------------------------------------
resource "aws_eip" "pmo" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name} - eip"
  })
}

# ---------------------------------------------------------------------------
# Volume secundario (10GB gp3) - diretorio da aplicacao + docker
# Recurso separado => nao e removido no termino da instancia (managed: false).
# ---------------------------------------------------------------------------
resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = var.data_volume.size
  type              = "gp3"
  iops              = var.data_volume.iops
  throughput        = var.data_volume.throughput

  tags = merge(local.common_tags, {
    Name = "${var.name} - data"
  })
}

# ---------------------------------------------------------------------------
# Instancia EC2 (SPOT)
# ---------------------------------------------------------------------------
resource "aws_instance" "pmo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone
  subnet_id              = var.subnet_id
  vpc_security_group_ids = concat(var.existing_security_group_ids, [aws_security_group.pmo_apps.id])
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name

  # Lifecycle: spot (persistent) - na interrupcao a instancia e parada (nao
  # terminada) e a AWS a relanca quando ha capacidade. persistent exige
  # instance_interruption_behavior = "stop" ou "hibernate" (nunca "terminate").
  instance_market_options {
    market_type = "spot"

    spot_options {
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  # Monitoring: disabled
  monitoring = false

  # Stop protection: disabled / Termination protection: disabled
  disable_api_stop        = false
  disable_api_termination = false

  # Stop-hibernate behavior: Disabled
  hibernation = false

  # Credit specification: standard (instancia burstable / familia T)
  credit_specification {
    cpu_credits = "standard"
  }

  # Enclaves Support: Disabled
  enclave_options {
    enabled = false
  }

  # Instance auto-recovery: Default
  # (Instance reboot migration ja e "Default (On)" na AWS; nao ha argumento no provider.)
  maintenance_options {
    auto_recovery = "default"
  }

  # Allow tags in instance metadata: Disabled
  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required" # IMDSv2
    instance_metadata_tags = "disabled"
  }

  # Disco raiz - 8GB gp3 (SO Ubuntu). managed: false => nao apagar no termino.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume.size
    iops                  = var.root_volume.iops
    throughput            = var.root_volume.throughput
    delete_on_termination = false

    tags = merge(local.common_tags, {
      Name = "${var.name} - root"
    })
  }

  # Provisionamento pos-boot (disco /data, Docker, app) fica a cargo do Ansible
  # (ansible/hml/pmo/). O cloud-init apenas atualiza o indice de pacotes.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {})

  # Obs.: nao usar volume_tags junto com root_block_device.tags (conflito no provider).
  tags = local.common_tags

  lifecycle {
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Anexa o volume secundario a instancia
# ---------------------------------------------------------------------------
resource "aws_volume_attachment" "data" {
  device_name = var.data_volume_device_name
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.pmo.id

  # Forca o detach no destroy sem depender de stop/start da instancia
  # (o volume nao e montado pelo cloud-init, entao nao ha risco de corrupcao).
  force_detach = true
}

# ---------------------------------------------------------------------------
# Associa o Elastic IP novo a instancia
# ---------------------------------------------------------------------------
resource "aws_eip_association" "pmo" {
  allocation_id = aws_eip.pmo.id
  instance_id   = aws_instance.pmo.id
}

# ---------------------------------------------------------------------------
# Repositorios ECR (cais-pmo-front / cais-pmo-back) - mesma configuracao
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "pmo" {
  for_each = var.ecr_repositories

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "pmo" {
  for_each = aws_ecr_repository.pmo

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove Untagged Images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove old homol images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["homol-"]
          countType     = "imageCountMoreThan"
          countNumber   = 2
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Remove old prod images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 2
        }
        action = { type = "expire" }
      },
    ]
  })
}
