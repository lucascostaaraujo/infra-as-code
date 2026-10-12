# =============================================================================
# Geral / rede
# =============================================================================

variable "region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "infra"
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}

variable "availability_zones" {
  description = "AZs das 2 subnets publicas (ALB e DB Subnet Group exigem >= 2 AZs)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_name" {
  description = "Nome (tag Name) da VPC"
  type        = string
  default     = "cais-infra"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.40.0.0/16"
}

variable "subnet_cidrs" {
  description = "CIDRs das subnets publicas, na mesma ordem de availability_zones"
  type        = list(string)
  default     = ["10.40.1.0/24", "10.40.2.0/24"]
}

# =============================================================================
# ECS
# =============================================================================

variable "cluster_name" {
  description = "Nome do cluster ECS"
  type        = string
  default     = "cais-infra"
}

variable "keycloak" {
  description = "Servico Keycloak (Fargate on-demand). cpu em unidades (2048 = 2 vCPU), memory em MiB."
  type = object({
    image         = string
    cpu           = number
    memory        = number
    desired_count = number
  })
  default = {
    image         = "quay.io/keycloak/keycloak:26.8.0"
    cpu           = 2048
    memory        = 4096
    desired_count = 1
  }
}

variable "keycloak_admin_username" {
  description = "Usuario admin inicial (bootstrap) do Keycloak"
  type        = string
  default     = "admin"
}

variable "gatus" {
  description = "Servico Gatus (Fargate on-demand). cpu em unidades (1024 = 1 vCPU), memory em MiB."
  type = object({
    image         = string
    cpu           = number
    memory        = number
    desired_count = number
  })
  default = {
    image         = "twinproduction/gatus:v5.37.0"
    cpu           = 1024
    memory        = 2048
    desired_count = 1
  }
}

variable "ephemeral_storage_gib" {
  description = <<-EOT
    Disco efemero das tasks (GiB). 20 e o padrao do Fargate (ja vem incluso),
    por isso o bloco ephemeral_storage so e declarado quando > 20 (a API
    aceita 21-200).
  EOT
  type        = number
  default     = 20
}

variable "s3_bucket_name" {
  description = "Bucket S3 de configuracoes (config do Gatus em gatus/config.yaml)"
  type        = string
  default     = "infra-cais"
}

variable "gatus_config" {
  description = <<-EOT
    Conteudo INICIAL do config.yaml do Gatus (so semeia o objeto no S3 na
    primeira criacao; depois disso edite pelo console do S3). Se null, usa o
    config de exemplo definido em ecs.tf (monitora o proprio Keycloak).
  EOT
  type        = string
  default     = null
}

# =============================================================================
# ALB
# =============================================================================

variable "alb_name" {
  description = "Nome do Application Load Balancer"
  type        = string
  default     = "cais-infra-alb"
}

variable "alb_allowed_cidr_blocks" {
  description = "CIDRs com acesso ao ALB (80/443)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "keycloak_hostname" {
  description = "Hostname do Keycloak (CNAME no Registro.br apontando para o DNS do ALB)"
  type        = string
  default     = "auth.institutocais.org.br"
}

variable "gatus_hostname" {
  description = "Hostname do Gatus (CNAME no Registro.br apontando para o DNS do ALB)"
  type        = string
  default     = "gatus.institutocais.org.br"
}

variable "enable_https" {
  description = <<-EOT
    Fase 2 do rollout: cria o listener 443 com o certificado ACM e faz o 80
    redirecionar para HTTPS. Deixe false no primeiro apply (o certificado
    precisa estar ISSUED, o que exige criar os CNAMEs de validacao no
    Registro.br - ver output acm_validation_records) e mude para true depois.
  EOT
  type        = bool
  default     = true
}

# =============================================================================
# RDS - postgresinfracais
# =============================================================================

variable "db_identifier" {
  description = "Identifier da instancia RDS"
  type        = string
  default     = "postgresinfracais"
}

variable "db_engine_version" {
  description = "Versao do engine Postgres (so major = a AWS escolhe a minor mais recente suportada)"
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  description = "Classe da instancia RDS"
  type        = string
  default     = "db.t4g.small"
}

variable "db_allocated_storage" {
  description = "Armazenamento (GB), gp3"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Database criado na instancia, usado pelo Keycloak"
  type        = string
  default     = "keycloak"
}

variable "db_username" {
  description = "Master user do RDS"
  type        = string
  default     = "postgres"
}

variable "db_allowed_cidr_blocks" {
  description = <<-EOT
    IPs (CIDR) liberados no security group do RDS para acesso direto
    (PGAdmin/psql), alem das tasks ECS. Vazio por padrao - adicione os IPs
    do time se precisar de acesso direto (a instancia e publicly_accessible,
    como no stack dev/pd-adata, mas so abre o que estiver listado aqui).
  EOT
  type        = list(string)
  default     = ["201.20.90.230/32"] # Lucas-Teste
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
  description = "Granularidade do Enhanced Monitoring (segundos). 0 = desligado (sem custo de CloudWatch Logs); ao ligar, e preciso recriar a role de monitoring em rds.tf."
  type        = number
  default     = 0
}
