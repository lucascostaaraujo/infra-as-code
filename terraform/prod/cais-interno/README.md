# CAIS-Interno Server - PRD

Provisiona a instância EC2 **CAIS-Interno Server - PRD** (On-Demand) na
`us-east-1a`, mais o Elastic IP e o disco secundário. Espelha
`terraform/hml/cais-interno/`, **sem** a criação de security groups, **sem**
repositórios ECR (ver abaixo) e **sem** market options de SPOT (instância
On-Demand, adequada para produção).

## Recursos criados

| Recurso | Descrição |
|---|---|
| `aws_instance.cais_interno` | EC2 On-Demand, Ubuntu 24.04, `t3a.medium`, monitoring off |
| `aws_ebs_volume.data` + `aws_volume_attachment.data` | Disco secundário 20GB gp3 anexado em `/dev/sdf` — 1º PV do LVM `data_vg` (montado em `/data` pelo Ansible) |
| `aws_ebs_volume.data_extra["<letra>"]` + `aws_volume_attachment.data_extra[*]` | Discos extras (via `additional_data_volumes`) para estender o VG `data_vg` — vazio por padrão |
| `aws_eip.cais_interno` + `aws_eip_association.cais_interno` | Elastic IP **novo** associado à instância |

Disco raiz: **10GB** gp3 (3000 IOPS / 125 MB/s), `delete_on_termination = false`.
Disco secundário: **20GB** gp3 (3000 IOPS / 125 MB/s), recurso independente — não é
removido quando a instância termina (`managed: false`). É o 1º Physical Volume do
Volume Group LVM `data_vg`; o LV `data_lv` (100% do VG) é montado em `/data` pelo
Ansible e recebe o `data-root` do Docker (`/data/docker`), o root do containerd
(`/data/containerd`) e os diretórios das aplicações (`/data/apps/*`).

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
`ansible/prod/cais-interno/README.md`). O `pvcreate` + `vgextend` + `lvextend` +
`resize2fs` acontecem online, sem recriar o filesystem.

## Security groups

Este stack **não cria** security groups. A instância sobe com
`security_group_ids` (default: `sg-0115b7b47a649de19` e `sg-09897c9030be1b5a6`) —
ambos **já existentes** e atribuídos no launch. `lifecycle.ignore_changes =
[vpc_security_group_ids]` impede o Terraform de reverter qualquer ajuste manual
feito depois diretamente na EC2.

## ECR

Este stack **não cria** repositórios ECR — todos os repositórios usados pelas
aplicações já existem (criados pelos stacks `farol` / `pmo`). O usuário/perfil de
deploy é configurado pelo Ansible (`ansible/prod/cais-interno/`).

## Pré-requisitos

- Instance profile `EC2SSMRole` existente (nome igual ao da role).
- Key pair `farol_06072026` existente na região.
- Security groups `sg-0115b7b47a649de19` e `sg-09897c9030be1b5a6` e subnet
  `subnet-000f83c5c32f47482` pertencentes à `vpc-0de609a7a328c8b5b`.

## Uso

```bash
cd terraform/prod/cais-interno
terraform init
terraform plan
terraform apply
```

## Observações

- **On-Demand**: sem `instance_market_options`, portanto sem risco de
  interrupção por falta de capacidade SPOT — adequado para o ambiente PRD.
- **Termination protection habilitada** (`disable_api_termination = true`): a
  instância não pode ser terminada via API/console/CLI enquanto a proteção
  estiver ativa. Para terminar/destruir de fato, desabilite antes (console ou
  `aws ec2 modify-instance-attribute --instance-id <id> --no-disable-api-termination`),
  ou ajuste `disable_api_termination = false` no `main.tf` e rode `terraform apply`
  antes do `terraform destroy`.
- O `cloud-init` apenas atualiza o índice de pacotes. Formatação/montagem do disco
  secundário (`/data`, via UUID no `fstab`), Docker, AWS CLI/ECR e aplicação ficam
  a cargo do Ansible — ver `ansible/prod/cais-interno/`.
- `credit_specification = standard` exige família burstable (T*). `t3a.medium`
  atende; ao trocar para não-burstable, remova o bloco `credit_specification`.
- `lifecycle.ignore_changes = [ami]` evita recriar a instância quando a Canonical
  publica uma nova imagem. Remova para forçar atualização da AMI.
