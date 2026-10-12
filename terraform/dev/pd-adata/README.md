# P&D-Adata - DEV

Stack completo (conta AWS **nova**) para o projeto P&D-Adata em `us-east-1`:
VPC/rede, EC2, key pair, ECR, S3 e RDS Postgres. Baseado no padrão dos stacks
`cais-interno`, adaptado para criar toda a infraestrutura de rede/suporte que
nos outros projetos já existia previamente na conta.

## Recursos criados

| Categoria | Recurso | Descrição |
|---|---|---|
| Rede | `aws_vpc.carrier` | VPC `carrier`, CIDR `10.30.0.0/16` |
| Rede | `aws_internet_gateway.carrier` | IGW `carrier-igw` |
| Rede | `aws_subnet.primary` / `.secondary` | 2 subnets públicas (`us-east-1a` e `us-east-1b`) — a segunda existe só para o DB Subnet Group do RDS |
| Rede | `aws_route_table.public` + associations | Rota `0.0.0.0/0` → IGW nas 2 subnets |
| IAM | `aws_iam_role.ssm` + `aws_iam_instance_profile.ssm` | Role `EC2SSMRole` novo (policy `AmazonSSMManagedInstanceCore`) — conta nova, não existe um já pronto para reusar |
| IAM | `aws_iam_role.rds_monitoring` | Role para o Enhanced Monitoring do RDS |
| Key pair | `tls_private_key` + `aws_key_pair.carrier` | Key pair `carrier_23092026`, criada nesta execução; `.pem` salvo local (gitignored) |
| EC2 | `aws_instance.pd_adata` | On-Demand, Ubuntu 24.04, `t3a.medium`, monitoring off, **sem inbound** (SSM only) |
| EC2 | `aws_ebs_volume.data` | 90GB gp3, montado em `/data` pelo Ansible |
| EC2 | `aws_eip.pd_adata` | Elastic IP novo |
| SG | `aws_security_group.ec2` | Sem regras de entrada — acesso só via SSM |
| SG | `aws_security_group.rds` | Entrada 5432 a partir do SG da EC2 + `var.db_allowed_cidr_blocks` (default `0.0.0.0/0` — acesso público liberado, ver seção abaixo) |
| ECR | `aws_ecr_repository.pd_adata["pd-adata-front"\|"pd-adata-back"]` | Mutable, scan on push, AES-256 |
| ECR | `aws_ecr_lifecycle_policy.pd_adata` | 3 regras (untagged / `dev-` / `homol-`) — ver abaixo |
| S3 | `aws_s3_bucket.pd_adata["pd-adata-anexos-dev"\|"pd-adata-rda-dev"\|"pd-adata-temp-dev"]` | Ver configuração completa abaixo |
| RDS | `aws_db_instance.postgrescarrier` | Postgres 14.22, `db.t4g.micro`, gp3 100GB — ver abaixo |

## Rede

Como esta é uma conta AWS nova, não há VPC/subnet pré-existente para reusar
(diferente dos stacks `cais-interno`/`farol`/`pmo`). A VPC `carrier`
(`10.30.0.0/16`) é criada com 2 subnets **públicas** (rota direta pro IGW):

- `10.30.1.0/24` em `us-east-1a` — onde a EC2 sobe.
- `10.30.2.0/24` em `us-east-1b` — existe só porque o RDS **exige** um DB
  Subnet Group com subnets em pelo menos 2 AZs, mesmo sendo Single-AZ.

Ambas são públicas só para manter o stack simples (sem NAT Gateway, que tem
custo fixo mensal); o RDS não fica de fato exposto à internet porque o
`aws_security_group.rds` só libera a porta 5432 a partir do security group da
EC2 — não há regra permitindo `0.0.0.0/0`.

## EC2 / Acesso

- **Sem inbound**: o security group da instância não tem nenhuma regra de
  entrada — o acesso é feito via **SSM Session Manager**. Se no futuro for
  necessário abrir portas (ex. HTTP/HTTPS direto), ajuste
  `aws_security_group.ec2` em `security_groups.tf`.
- **IAM Role para SSM**: como é conta nova, o Terraform cria o role
  `EC2SSMRole` do zero (`iam.tf`), com a policy gerenciada
  `AmazonSSMManagedInstanceCore`.
- **Key pair**: `carrier_23092026` é gerada nesta execução
  (`tls_private_key` + `aws_key_pair`). A chave privada é salva em
  `carrier_23092026.pem` nesta mesma pasta — **gitignored**
  (`terraform/.gitignore`, padrão `*.pem`). Guarde-a em local seguro fora do
  repo após o apply; ela também fica no `terraform.tfstate` (não versionado).
- Discos: raiz 10GB gp3 (SO) + `/data` 90GB gp3 (Docker/app, montado pelo
  Ansible — `ansible/dev/pd-adata/`, a ser ajustado depois deste Terraform).

## ECR

Repositórios `pd-adata-front` e `pd-adata-back`, ambos com:

- Tag mutability: **Mutable**
- Scan frequency: **Scan on push**
- Encryption type: **AES-256** (SSE-S3, não KMS)

Lifecycle policy (idêntica nos dois repositórios):

| Prioridade | Descrição | Tag status | Filtro | Critério | Ação |
|---|---|---|---|---|---|
| 1 | Remove Untagged Images | Untagged | — | Dias desde o push: 1 | Expire |
| 2 | Remove old dev images | Tagged | `dev-` | Limite de imagens: 2 | Expire |
| 3 | Remove old homol images | Tagged | `homol-` | Limite de imagens: 2 | Expire |

## S3

Buckets `pd-adata-anexos-dev`, `pd-adata-rda-dev` e `pd-adata-temp-dev`, general
purpose, todos privados. Configuração:

| Opção | Valor | Como foi implementado |
|---|---|---|
| Bucket Versioning | Disabled | Default AWS — nenhum recurso `aws_s3_bucket_versioning` criado |
| MFA Delete | Disabled | Default AWS (dependente de versioning) |
| Encryption | SSE-S3 (AES-256) | `aws_s3_bucket_server_side_encryption_configuration` |
| Bucket Key | Disabled | `bucket_key_enabled = false` no recurso acima |
| Blocked encryption types | SSE-C | `aws_s3_bucket_policy` — nega `PutObject` com header de SSE-C (não existe argumento dedicado no provider AWS para isso) |
| Server access logging | Disabled | Default AWS — sem `aws_s3_bucket_logging` |
| Notificações ao EventBridge | Off | Default AWS — sem `aws_s3_bucket_notification` |
| Transfer acceleration | Disabled | Default AWS — sem `aws_s3_bucket_accelerate_configuration` |
| Object Lock | Disabled | Default AWS — `object_lock_enabled` não definido (não pode ser mudado depois de criado) |
| Requester Pays | Disabled | Default AWS — sem `aws_s3_bucket_request_payment_configuration` |
| Static website hosting | Disabled | Default AWS — sem `aws_s3_bucket_website_configuration` |
| Block all public access | **On** | `aws_s3_bucket_public_access_block` com os 4 flags `true` |

## RDS - postgrescarrier

| Opção | Valor |
|---|---|
| Engine / versão | PostgreSQL 14.22 |
| Instance class | `db.t4g.micro` |
| Multi-AZ | Não |
| RDS Extended Support | Enabled (`engine_lifecycle_support = "open-source-rds-extended-support"`) |
| License model | `postgresql-license` |
| Master username | `postgres` |
| Senha | Gerada via `random_password`, **sensitive** — `terraform output -raw db_password` |
| IAM DB authentication | Not enabled |
| Encryption (storage) | Not enabled |
| Storage | gp3, 100GB, autoscaling **desabilitado** — `iops`/`storage_throughput` não são especificados (abaixo de 400GB a API do RDS rejeita esses argumentos; o baseline aplicado automaticamente já é 3000 IOPS / 125 MiBps) |
| Enhanced Monitoring | Enabled, granularidade 60s (`aws_iam_role.rds_monitoring`) |
| Database Insights | Standard (`database_insights_mode = "standard"`) |
| Auto minor version upgrade | Enabled |
| Automated backups | Enabled, 7 dias |
| Backup window | `03:00-04:00` UTC |
| Copy tags to snapshot | Enabled |
| Backup target | AWS Cloud (region) |
| Deletion protection | **Enabled** |

## Acesso ao RDS via PGAdmin / psql

O RDS é `publicly_accessible = true` e o security group (`db_allowed_cidr_blocks`,
default `["0.0.0.0/0"]`) libera a porta 5432 para qualquer IP — decisão
deliberada porque várias pessoas do time precisam acessar o banco diretamente
via PGAdmin, não só a partir da EC2. A única barreira de acesso é a
autenticação do Postgres (usuário/senha).

> ⚠️ Isso expõe a porta 5432 publicamente à internet, não só ao time — bots de
> varredura vão encontrar a porta aberta. A senha é forte (gerada
> aleatoriamente, 24 caracteres — `terraform output -raw db_password`) e o
> `deletion_protection` está ativo, mas vale ter esse trade-off em mente. Para
> restringir a IPs específicos no futuro, ajuste `db_allowed_cidr_blocks`
> (ex. `-var='db_allowed_cidr_blocks=["203.0.113.10/32"]'`) e rode `apply`.

No PGAdmin, conecte com:
- Host: `terraform output -raw db_address`
- Port: `5432`
- Username: `postgres`
- Password: `terraform output -raw db_password`

> ⚠️ Dois itens do escopo pedido (**"Database counter metrics: Disabled"** e
> **"Architecture settings: Non-multitenant architecture"**) não têm um
> argumento confirmado e estável no provider `hashicorp/aws` até onde
> temos certeza — para não arriscar quebrar o `apply` com um atributo
> incorreto, eles **não foram configurados via Terraform**. Confira no
> console após o apply e ajuste manualmente se necessário.

Como `deletion_protection = true`, um `terraform destroy` vai falhar até você
desabilitar a proteção manualmente (console, ou `disable_api_termination`-like
via `aws rds modify-db-instance --no-deletion-protection`) ou mudar o valor no
`rds.tf` e rodar `apply` antes do `destroy`.

## Pré-requisitos

- Credenciais AWS da conta nova configuradas (`aws configure` / variáveis de
  ambiente) com permissão para criar VPC, EC2, IAM, ECR, S3 e RDS.
- Nomes globalmente únicos: os buckets S3 (`pd-adata-anexos-dev`,
  `pd-adata-rda-dev`, `pd-adata-temp-dev`) precisam estar livres
  **globalmente** (todos os buckets S3 do mundo
  compartilham o mesmo namespace) — se já existirem em outra conta, o apply
  falha e será preciso escolher outro nome.

## Uso

```bash
cd terraform/dev/pd-adata
terraform init
terraform plan
terraform apply
```

Depois do apply:
```bash
terraform output -raw public_ip          # IP da EC2
terraform output -raw db_endpoint        # host:porta do RDS
terraform output -raw db_password        # senha do master user (sensitive)
ls carrier_23092026.pem                  # chave privada gerada
chmod 600 carrier_23092026.pem
```

## Observações

- **On-Demand**: sem `instance_market_options` — sem risco de interrupção por
  falta de capacidade SPOT.
- O `cloud-init` só atualiza o índice de pacotes; disco `/data`, Docker e
  aplicação ficam a cargo do Ansible (`ansible/dev/pd-adata/`, ainda a criar).
- `credit_specification = standard` exige família burstable (T*); `t3a.medium`
  atende.
- `lifecycle.ignore_changes = [ami]` evita recriar a instância quando a
  Canonical publica uma nova imagem.
- Buckets, repositórios ECR e o RDS **não têm** `prevent_destroy` — o único
  freio a um `destroy` acidental é o `deletion_protection` do RDS.
