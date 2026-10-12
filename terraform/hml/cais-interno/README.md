# CAIS-Interno Server - HML

Provisiona a instância EC2 **CAIS-Interno Server - HML** (SPOT) na `us-east-1a`,
mais o Elastic IP e o disco secundário. Espelha `terraform/hml/pmo/`, **sem** a
criação de security groups e **sem** repositórios ECR (ver abaixo).

## Recursos criados

| Recurso | Descrição |
|---|---|
| `aws_instance.cais_interno` | EC2 SPOT persistent, Ubuntu 24.04, `t3a.medium`, monitoring off |
| `aws_ebs_volume.data` + `aws_volume_attachment.data` | Disco secundário 20GB gp3 anexado em `/dev/sdf` — 1º PV do LVM `data_vg` (montado em `/data` pelo Ansible) |
| `aws_ebs_volume.data_extra["<letra>"]` + `aws_volume_attachment.data_extra[*]` | Discos extras (via `additional_data_volumes`) para estender o VG `data_vg` — vazio por padrão |
| `aws_eip.cais_interno` + `aws_eip_association.cais_interno` | Elastic IP **novo** associado à instância |

Disco raiz: **10GB** gp3 (3000 IOPS / 125 MB/s), `delete_on_termination = false`.
Disco secundário: **20GB** gp3 (3000 IOPS / 125 MB/s), recurso independente — não é
removido quando a instância termina (`managed: false`). É o 1º Physical Volume do
Volume Group LVM `data_vg`; o LV `data_lv` (100% do VG) é montado em `/data` pelo
Ansible e recebe o `data-root` do Docker (`/data/docker`) e os diretórios das
aplicações (`/data/apps/*`).

### Ampliar o `/data` depois

O `/data` é LVM, então é possível aumentá-lo só adicionando disco:

```hcl
# terraform.tfvars (ou -var)
additional_data_volumes = {
  g = { size = 50 }   # novo disco gp3 de 50GB, anexado em /dev/sdg
}
```

`terraform apply` e então, na instância, rode o Ansible com `--tags data_volume`
após acrescentar o device novo em `data_volume_devices` (ver
`ansible/hml/cais-interno/README.md`). O `pvcreate` + `vgextend` + `lvextend` +
`resize2fs` acontecem online, sem recriar o filesystem.

## Security groups

Este stack **não cria** security groups. A instância sobe com
`security_group_ids` (default: `sg-0115b7b47a649de19`) apenas para ficar acessível
via SSM; os SGs desejados — que **já existem** — são atribuídos **manualmente na
EC2 após a criação**. `lifecycle.ignore_changes = [vpc_security_group_ids]` impede
o Terraform de reverter esses anexos manuais em execuções futuras.

## ECR

Este stack **não cria** repositórios ECR — todos os repositórios usados pelas
aplicações já existem (criados pelos stacks `farol` / `pmo`). O usuário/perfil de
deploy é configurado pelo Ansible (`ansible/hml/cais-interno/`).

## Pré-requisitos

- Instance profile `EC2SSMRole` existente (nome igual ao da role).
- Key pair `farol_06072026` existente na região.
- Security group `sg-0115b7b47a649de19` e subnet `subnet-000f83c5c32f47482`
  pertencentes à `vpc-0de609a7a328c8b5b`.

## Uso

```bash
cd terraform/hml/cais-interno
terraform init
terraform plan
terraform apply
```

## Observações

- **SPOT persistent** (`spot_options.spot_instance_type = "persistent"`,
  `instance_interruption_behavior = "stop"`): em caso de interrupção a instância é
  **parada** (não terminada) e a AWS a relança automaticamente quando há
  capacidade na AZ. Disco secundário e Elastic IP são preservados.
- **`terraform destroy`**: com spot persistent, o provider cancela a spot request
  ao terminar a instância. Confira depois se não sobrou request ativa:
  `aws ec2 describe-spot-instance-requests --filters "Name=state,Values=open,active"`.
- O `cloud-init` apenas atualiza o índice de pacotes. Formatação/montagem do disco
  secundário (`/data`, via UUID no `fstab`), Docker, AWS CLI/ECR e aplicação ficam
  a cargo do Ansible — ver `ansible/hml/cais-interno/`.
- `credit_specification = standard` exige família burstable (T*). `t3a.medium`
  atende; ao trocar para não-burstable, remova o bloco `credit_specification`.
- `lifecycle.ignore_changes = [ami]` evita recriar a instância quando a Canonical
  publica uma nova imagem. Remova para forçar atualização da AMI.
