# =============================================================================
# Geral / rede
# =============================================================================

variable "region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone primaria (EC2, volumes, subnet publica principal)"
  type        = string
  default     = "us-east-1a"
}

variable "availability_zone_secondary" {
  description = <<-EOT
    Segunda AZ, usada so para a segunda subnet exigida pelo DB Subnet Group do
    RDS (a AWS exige subnets em pelo menos 2 AZs, mesmo para instancia Single-AZ).
  EOT
  type        = string
  default     = "us-east-1b"
}

variable "vpc_name" {
  description = "Nome (tag Name) da VPC"
  type        = string
  default     = "carrier"
}

variable "igw_name" {
  description = "Nome (tag Name) do Internet Gateway"
  type        = string
  default     = "carrier-igw"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR da subnet publica primaria (EC2), na availability_zone"
  type        = string
  default     = "10.30.1.0/24"
}

variable "subnet_cidr_secondary" {
  description = "CIDR da subnet publica secundaria (so p/ DB Subnet Group), na availability_zone_secondary"
  type        = string
  default     = "10.30.2.0/24"
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}

# =============================================================================
# EC2 - P&D-Adata Server
# =============================================================================

variable "name" {
  description = "Nome (tag Name) da instancia"
  type        = string
  default     = "P&D-Adata Server - DEV"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "Tipo da instancia (burstable/T para suportar credit_specification = standard)"
  type        = string
  default     = "t3a.medium"
}

variable "key_name" {
  description = "Nome da key pair criada por este stack (tls_private_key + aws_key_pair)"
  type        = string
  default     = "carrier_23092026"
}

variable "iam_instance_profile" {
  description = "Nome do IAM Role / Instance Profile criado por este stack para o SSM"
  type        = string
  default     = "EC2SSMRole"
}

variable "root_volume" {
  description = "Volume raiz (SO Ubuntu) - 10GB gp3"
  type = object({
    size       = number
    iops       = number
    throughput = number
  })
  default = {
    size       = 10
    iops       = 3000
    throughput = 125
  }
}

variable "data_volume" {
  description = "Volume secundario, montado em /data pelo Ansible - 90GB gp3"
  type = object({
    size       = number
    iops       = number
    throughput = number
  })
  default = {
    size       = 90
    iops       = 3000
    throughput = 125
  }
}

variable "data_volume_device_name" {
  description = "Device name do volume secundario no bloco de mapeamento da instancia"
  type        = string
  default     = "/dev/sdf"
}

variable "additional_data_volumes" {
  description = <<-EOT
    Discos gp3 extras para estender o /data no futuro (mesmo padrao usado no
    cais-interno, caso o Ansible venha a gerenciar /data via LVM). Vazio por
    padrao. A chave e a letra do device (ex. "g" => anexado em /dev/sdg).
  EOT
  type = map(object({
    size       = number
    iops       = optional(number, 3000)
    throughput = optional(number, 125)
  }))
  default = {}
}

variable "data_mount_point" {
  description = "Ponto de montagem do volume secundario (configurado pelo Ansible; mantido aqui como documentacao)"
  type        = string
  default     = "/data"
}

# =============================================================================
# ECR
# =============================================================================

variable "ecr_repository_names" {
  description = "Nomes dos repositorios ECR a criar"
  type        = set(string)
  default     = ["pd-adata-front", "pd-adata-back"]
}

# =============================================================================
# S3
# =============================================================================

variable "s3_bucket_names" {
  description = "Nomes dos buckets S3 a criar (general purpose)"
  type        = set(string)
  default     = ["pd-adata-anexos-dev", "pd-adata-rda-dev", "pd-adata-temp-dev"]
}

# =============================================================================
# RDS - postgrescarrier
# =============================================================================

variable "db_identifier" {
  description = "Identifier da instancia RDS"
  type        = string
  default     = "postgrescarrier"
}

variable "db_engine_version" {
  description = "Versao do engine Postgres"
  type        = string
  default     = "14.22"
}

variable "db_allowed_cidr_blocks" {
  description = <<-EOT
    IPs (CIDR) liberados no security group do RDS para acesso direto
    (PGAdmin/psql), alem da EC2. Default "0.0.0.0/0" - varias pessoas do time
    precisam acessar o banco diretamente, entao o acesso fica liberado pra
    qualquer IP (a autenticacao do Postgres, com a senha gerada, continua
    sendo a unica barreira). Restrinja a CIDRs especificos aqui se isso mudar.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db2_identifier" {
  description = "Identifier da segunda instancia RDS, restaurada a partir de um snapshot da postgrescarrier"
  type        = string
  default     = "postgresadata"
}

variable "db2_instance_class" {
  description = "Classe da segunda instancia RDS (postgresadata)"
  type        = string
  default     = "db.t4g.small"
}

variable "db2_snapshot_identifier" {
  description = <<-EOT
    Snapshot de origem do restore da postgresadata. Pode ser um snapshot
    automatico (prefixo "rds:", gerado pelo backup diario) ou manual. So
    importa no momento da criacao (ver lifecycle.ignore_changes em
    rds_postgresadata.tf).
  EOT
  type        = string
  default     = "rds:postgrescarrier-2026-09-30-10-06"
}

variable "db_backup_retention_period" {
  description = "Retencao dos backups automatizados (dias)"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Janela de backup automatizado (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "db_monitoring_interval" {
  description = "Granularidade do Enhanced Monitoring (segundos)"
  type        = number
  default     = 60
}
