locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "pd-adata"
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
resource "aws_eip" "pd_adata" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name} - eip"
  })
}

# ---------------------------------------------------------------------------
# Volume secundario (90GB gp3), montado em /data pelo Ansible.
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
# Discos extras para estender o /data no futuro (vazio por padrao).
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
# Sem inbound (acesso via SSM). O security group da instancia (aws_security_group.ec2,
# em security_groups.tf) so libera trafego de saida.
# ---------------------------------------------------------------------------
resource "aws_instance" "pd_adata" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone
  subnet_id              = aws_subnet.primary.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
  key_name               = aws_key_pair.carrier.key_name

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
  # (ansible/dev/pd-adata/). O cloud-init apenas atualiza o indice de pacotes.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {})

  # Obs.: nao usar volume_tags junto com root_block_device.tags (conflito no provider).
  # autoOnOff=true -> gerenciada pela Lambda de liga/desliga (ver autooff.tf).
  tags = merge(local.common_tags, { Name = var.name, autoOnOff = "true" })

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
  instance_id = aws_instance.pd_adata.id

  # Forca o detach no destroy sem depender de stop/start da instancia
  # (o volume nao e montado pelo cloud-init, entao nao ha risco de corrupcao).
  force_detach = true
}

# ---------------------------------------------------------------------------
# Anexa os discos extras - /dev/sd<letra da chave>
# ---------------------------------------------------------------------------
resource "aws_volume_attachment" "data_extra" {
  for_each = var.additional_data_volumes

  device_name  = "/dev/sd${each.key}"
  volume_id    = aws_ebs_volume.data_extra[each.key].id
  instance_id  = aws_instance.pd_adata.id
  force_detach = true
}

# ---------------------------------------------------------------------------
# Associa o Elastic IP novo a instancia
# ---------------------------------------------------------------------------
resource "aws_eip_association" "pd_adata" {
  allocation_id = aws_eip.pd_adata.id
  instance_id   = aws_instance.pd_adata.id
}
