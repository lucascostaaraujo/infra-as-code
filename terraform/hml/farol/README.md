# Farol Server HML

Provisiona a instância EC2 **Farol Server HML** (SPOT) na `us-east-1a`.

## Recursos criados

| Recurso | Descrição |
|---|---|
| `aws_instance.farol` | EC2 SPOT persistent, Ubuntu 24.04, `t3.medium` (ajustável), monitoring off |
| `aws_ebs_volume.data` + `aws_volume_attachment.data` | Disco de dados 10GB gp3 anexado em `/dev/sdf` (formatado/montado em `/data` pelo Ansible) |
| `aws_eip_association.farol` | Associa o Elastic IP existente `18.214.67.166` |

Disco raiz: 8GB gp3 (3000 IOPS / 125 MB/s), `delete_on_termination = false`.
Disco de dados: 10GB gp3 (3000 IOPS / 125 MB/s), recurso independente — não é
removido quando a instância termina (`managed: false`).

## Pré-requisitos

- Elastic IP `18.214.67.166` já alocado na conta.
- Instance profile `EC2SSMRole` existente (nome igual ao da role).
- Key pair `farol_06072026` existente na região.
- Security groups e subnet informados pertencentes à `vpc-0de609a7a328c8b5b`.

## Uso

```bash
cd terraform/hml/farol
terraform init
terraform plan
terraform apply
```

## Observações

- **SPOT persistent** (`spot_options.spot_instance_type = "persistent"`,
  `instance_interruption_behavior = "stop"`): em caso de interrupção a instância é
  **parada** (não terminada) e a AWS a relança automaticamente quando há
  capacidade na AZ. Disco de dados e Elastic IP são preservados.
- **`terraform destroy`**: com spot persistent, o provider cancela a spot request
  ao terminar a instância. Confira depois se não sobrou request ativa:
  `aws ec2 describe-spot-instance-requests --filters "Name=state,Values=open,active"`.
- O `cloud-init` apenas atualiza o índice de pacotes. Formatação/montagem do
  disco de dados (`/data`, via UUID no `fstab`), Docker e aplicação ficam a
  cargo do Ansible — ver `ansible/hml/farol/`.
- `credit_specification = standard` exige família burstable (T*). Ao trocar
  `instance_type` para não-burstable, remova o bloco `credit_specification` em `main.tf`.
- `lifecycle.ignore_changes = [ami]` evita recriar a instância quando a Canonical
  publica uma nova imagem. Remova para forçar atualização da AMI.
