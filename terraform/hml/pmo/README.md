# Cais-pmo Server - HML

Provisiona a instância EC2 **Cais-pmo Server - HML** (SPOT) na `us-east-1a`, mais o
Elastic IP, o security group `PMO_Apps` e os repositórios ECR do PMO.

## Recursos criados

| Recurso | Descrição |
|---|---|
| `aws_instance.pmo` | EC2 SPOT persistent, Ubuntu 24.04, `t3a.medium`, monitoring off |
| `aws_ebs_volume.data` + `aws_volume_attachment.data` | Disco secundário 10GB gp3 anexado em `/dev/sdf` (formatado/montado em `/data` pelo Ansible) |
| `aws_eip.pmo` + `aws_eip_association.pmo` | Elastic IP **novo** associado à instância |
| `aws_security_group.pmo_apps` (+ ingress/egress rules) | SG `PMO_Apps` (NPM: 80, 443, 81) |
| `aws_ecr_repository.pmo["cais-pmo-front"\|"cais-pmo-back"]` | Repositórios ECR (AES-256, scan on push, mutable) |
| `aws_ecr_lifecycle_policy.pmo[*]` | 3 lifecycle rules por repositório |

Disco raiz: 8GB gp3 (3000 IOPS / 125 MB/s), `delete_on_termination = false`.
Disco secundário: 10GB gp3 (3000 IOPS / 125 MB/s), recurso independente — não é
removido quando a instância termina (`managed: false`).

### Security groups anexados à instância

- `sg-0115b7b47a649de19` — já existente (via `existing_security_group_ids`)
- `PMO_Apps` — criado aqui:

| Porta | Protocolo | Origem | Descrição |
|---|---|---|---|
| 80 | TCP | 0.0.0.0/0 | NPM |
| 443 | TCP | 0.0.0.0/0 | NPM |
| 81 | TCP | 201.20.127.197/32 | Lucas-IP NPM Dash |
| 81 | TCP | 10.20.0.0/16 | - |

Egress: liberado (`0.0.0.0/0`, all protocols), equivalente ao padrão do console.

### ECR — lifecycle policy (idêntica em `cais-pmo-front` e `cais-pmo-back`)

| Prioridade | Descrição | Seleção | Ação |
|---|---|---|---|
| 1 | Remove Untagged Images | untagged, `sinceImagePushed` > 1 dia | expire |
| 2 | Remove old homol images | tagged `homol-`, `imageCountMoreThan` 2 | expire |
| 3 | Remove old prod images | tagged `prod-`, `imageCountMoreThan` 2 | expire |

> Observação: o ECR não tem critério "days since created"; o equivalente para
> imagens sem tag é `sinceImagePushed` (dias desde o push), usado na regra 1.

## Pré-requisitos

- Instance profile `EC2SSMRole` existente (nome igual ao da role).
- Key pair `farol_06072026` existente na região.
- Security group `sg-0115b7b47a649de19` e subnet `subnet-000f83c5c32f47482`
  pertencentes à `vpc-0de609a7a328c8b5b`.

## Uso

```bash
cd terraform/hml/pmo
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
  a cargo do Ansible — ver `ansible/hml/pmo/`.
- `credit_specification = standard` exige família burstable (T*). `t3a.medium`
  atende; ao trocar para não-burstable, remova o bloco `credit_specification`.
- `lifecycle.ignore_changes = [ami]` evita recriar a instância quando a Canonical
  publica uma nova imagem. Remova para forçar atualização da AMI.
