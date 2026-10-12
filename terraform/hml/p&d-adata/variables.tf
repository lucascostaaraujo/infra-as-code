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
  default     = "CAIS-Interno Server - HML"
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

variable "security_group_ids" {
  description = <<-EOT
    Security groups JA existentes anexados a instancia no launch. Este stack NAO
    cria security groups: os SGs desejados sao atribuidos manualmente na EC2 apos
    a criacao. O valor aqui garante apenas que a instancia sobe acessivel (SSM);
    `lifecycle.ignore_changes` evita que o Terraform reverta os SGs anexados a mao.
  EOT
  type        = list(string)
  default = [
    "sg-0115b7b47a649de19",
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
  description = "Volume secundario (1o PV do LVM data_vg, montado em /data pelo Ansible) - 20GB gp3"
  type = object({
    size       = number
    iops       = number
    throughput = number
  })
  default = {
    size       = 20
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
    Discos gp3 extras para ESTENDER o Volume Group LVM `data_vg` no futuro, sem
    recriar nada. A chave e a letra do device (ex. "g" => anexado em /dev/sdg).
    Depois do apply: rode `lsblk` na instancia, acrescente o device novo em
    `data_volume_devices` (ansible/.../group_vars/cais_interno_hml/main.yml) e
    rode `ansible-playbook site.yml --tags data_volume`.
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

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
