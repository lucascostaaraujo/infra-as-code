locals {
  common_tags = merge(
    {
      Name        = var.name
      Environment = var.environment
      Project     = "cais-interno"
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
# Elastic IP novo
# ---------------------------------------------------------------------------
resource "aws_eip" "cais_interno" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name} - eip"
  })
}

# ---------------------------------------------------------------------------
# Volume secundario (20GB gp3) - 1o Physical Volume do LVM `data_vg`, montado em
# /data pelo Ansible (Docker data-root + diretorios da aplicacao).
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
# Discos extras para estender o Volume Group LVM `data_vg` no futuro.
# Vazio por padrao (var.additional_data_volumes = {}).
# ---------------------------------------------------------------------------
resource "aws_ebs_volume" "data_extra" {
  for_each = var.additional_data_volumes

  availability_zone = var.availability_zone
  size              = each.value.size
  type              = "gp3"
  iops              = each.value.iops
  throughput        = each.value.throughput

  tags = merge(local.common_tags, {
    Name = "${var.name} - data-${each.key}"
  })
}

# ---------------------------------------------------------------------------
# Instancia EC2 (On-Demand)
#
# Este stack NAO cria security groups. Os SGs desejados (que ja existem) sao
# atribuidos manualmente na EC2 apos a criacao. O `security_group_ids` abaixo
# serve so para a instancia subir acessivel; `ignore_changes` impede o Terraform
# de reverter os SGs anexados a mao em execucoes futuras.
# ---------------------------------------------------------------------------
resource "aws_instance" "cais_interno" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name

  # Instancia On-Demand (sem instance_market_options => nao e spot).

  # Monitoring: disabled
  monitoring = false

  # Stop protection: disabled / Termination protection: enabled
  disable_api_stop        = false
  disable_api_termination = true

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

  # Disco raiz - 10GB gp3 (SO Ubuntu). managed: false => nao apagar no termino.
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
  # (ansible/prod/cais-interno/). O cloud-init apenas atualiza o indice de pacotes.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {})

  # Obs.: nao usar volume_tags junto com root_block_device.tags (conflito no provider).
  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      ami,
      vpc_security_group_ids, # SGs atribuidos manualmente na EC2 apos a criacao
    ]
  }
}

# ---------------------------------------------------------------------------
# Anexa o volume secundario a instancia
# ---------------------------------------------------------------------------
resource "aws_volume_attachment" "data" {
  device_name = var.data_volume_device_name
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.cais_interno.id

  # Forca o detach no destroy sem depender de stop/start da instancia
  # (o volume nao e montado pelo cloud-init, entao nao ha risco de corrupcao).
  force_detach = true
}

# ---------------------------------------------------------------------------
# Anexa os discos extras (LVM data_vg) - /dev/sd<letra da chave>
# ---------------------------------------------------------------------------
resource "aws_volume_attachment" "data_extra" {
  for_each = var.additional_data_volumes

  device_name  = "/dev/sd${each.key}"
  volume_id    = aws_ebs_volume.data_extra[each.key].id
  instance_id  = aws_instance.cais_interno.id
  force_detach = true
}

# ---------------------------------------------------------------------------
# Associa o Elastic IP novo a instancia
# ---------------------------------------------------------------------------
resource "aws_eip_association" "cais_interno" {
  allocation_id = aws_eip.cais_interno.id
  instance_id   = aws_instance.cais_interno.id
}
