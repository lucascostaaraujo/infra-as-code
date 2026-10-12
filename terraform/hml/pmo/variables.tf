variable "region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone da instancia e dos volumes"
  type        = string
  default     = "us-east-1a"
}

variable "name" {
  description = "Nome (tag Name) da instancia"
  type        = string
  default     = "Cais-pmo Server - HML"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "hml"
}

variable "instance_type" {
  description = "Tipo da instancia (burstable/T para suportar credit_specification = standard)"
  type        = string
  default     = "t3a.medium"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = "vpc-0de609a7a328c8b5b"
}

variable "subnet_id" {
  description = "Subnet ID (deve estar na availability_zone informada)"
  type        = string
  default     = "subnet-000f83c5c32f47482"
}

variable "existing_security_group_ids" {
  description = "Security groups JA existentes que serao anexados a instancia"
  type        = list(string)
  default = [
    "sg-0115b7b47a649de19",
  ]
}

variable "pmo_apps_ingress_rules" {
  description = "Regras de entrada do security group PMO_Apps"
  type = map(object({
    description = string
    from_port   = number
    to_port     = number
    ip_protocol = string
    cidr_ipv4   = string
  }))
  default = {
    http = {
      description = "NPM"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    npm_dash_lucas = {
      description = "Lucas-IP NPM Dash"
      from_port   = 81
      to_port     = 81
      ip_protocol = "tcp"
      cidr_ipv4   = "201.20.127.197/32"
    }
    https = {
      description = "NPM"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    npm_dash_vpc = {
      description = "-"
      from_port   = 81
      to_port     = 81
      ip_protocol = "tcp"
      cidr_ipv4   = "10.20.0.0/16"
    }
  }
}

variable "iam_instance_profile" {
  description = "Nome do instance profile (normalmente igual ao nome da role: EC2SSMRole)"
  type        = string
  default     = "EC2SSMRole"
}

variable "key_name" {
  description = "Key pair associada no launch"
  type        = string
  default     = "farol_06072026"
}

variable "root_volume" {
  description = "Volume raiz (SO Ubuntu) - 8GB gp3"
  type = object({
    size       = number
    iops       = number
    throughput = number
  })
  default = {
    size       = 8
    iops       = 3000
    throughput = 125
  }
}

variable "data_volume" {
  description = "Volume secundario (diretorio da aplicacao + docker) - 10GB gp3"
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

variable "data_volume_device_name" {
  description = "Device name do volume secundario no bloco de mapeamento da instancia"
  type        = string
  default     = "/dev/sdf"
}

variable "data_mount_point" {
  description = "Ponto de montagem do volume secundario (configurado pelo Ansible; mantido aqui como documentacao)"
  type        = string
  default     = "/data"
}

variable "ecr_repositories" {
  description = "Repositorios ECR a criar (mesma configuracao para todos)"
  type        = set(string)
  default = [
    "cais-pmo-front",
    "cais-pmo-back",
  ]
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
