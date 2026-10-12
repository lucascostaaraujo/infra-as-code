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
  default     = "Farol Server HML"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "hml"
}

variable "instance_type" {
  description = "Tipo da instancia (burstable/T para suportar credit_specification = standard)"
  type        = string
  default     = "t3.medium"
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

variable "security_group_ids" {
  description = "Security groups associados a instancia"
  type        = list(string)
  default = [
    "sg-0115b7b47a649de19",
    "sg-0ff605defef7407e4",
    "sg-028b801cd876214ef",
  ]
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

variable "eip_public_ip" {
  description = "IP publico do Elastic IP ja existente que sera associado a instancia"
  type        = string
  default     = "18.214.67.166"
}

variable "root_volume" {
  description = "Volume raiz (aplicacao / SO) - 8GB gp3"
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
  description = "Volume de dados (diretorio da aplicacao + docker) - 10GB gp3"
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
  description = "Device name do volume de dados no bloco de mapeamento da instancia"
  type        = string
  default     = "/dev/sdf"
}

variable "data_mount_point" {
  description = "Ponto de montagem do volume de dados (configurado pelo Ansible; mantido aqui como documentacao)"
  type        = string
  default     = "/data"
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
