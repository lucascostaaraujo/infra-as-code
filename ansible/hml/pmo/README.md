# Ansible — PMO Server HML

Provisionamento pós-boot da instância **PMO Server HML** (criada pelo Terraform
em `terraform/hml/pmo/`). Espelha `ansible/hml/farol/`, com a estrutura de pastas
do PMO e configuração de AWS CLI / ECR.

## O que o playbook faz

| Role | Ações |
|---|---|
| `common` | `apt update` + `dist-upgrade`, utilitários básicos, reboot se exigido |
| `data_volume` | formata o volume de 10GB, monta em `/data` **via UUID no `/etc/fstab`** (backup do fstab antes), `mount -a` + `daemon-reload`, cria a estrutura de diretórios |
| `docker` | instala Docker Engine + Compose (repo oficial), move o `data-root` para `/data/docker`, habilita no boot, adiciona `ubuntu` ao grupo `docker` |
| `aws_cli` | instala AWS CLI v2, grava `~/.aws/{config,credentials}` (perfil `cais_pmo_deploy`), instala `amazon-ecr-credential-helper` e configura `~/.docker/config.json` para push/pull no ECR sem `docker login` manual |

Estrutura de diretórios criada:

```
/data
├── apps
│   ├── cais-pmo-back-homol
│   ├── cais-pmo-front-homol
│   └── proxy
└── docker            # data-root do Docker
```

## Pré-requisitos

- Instância criada e acessível via SSH (usuário `ubuntu`, key pair
  `farol_06072026`).
- Chave privada em `~/.ssh/farol_06072026.pem` (ajuste em `inventory.ini`).
- `ansible_host` em `inventory.ini` = Elastic IP novo da instância:
  ```bash
  terraform -chdir=../../../terraform/hml/pmo output -raw public_ip
  ```
- Ansible 2.15+ e as collections:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

## Credenciais (fora do Git)

O secret **não** é versionado. Antes do primeiro run:

```bash
cp group_vars/pmo_hml/secrets.yml.example group_vars/pmo_hml/secrets.yml
# editar group_vars/pmo_hml/secrets.yml com a access key / secret do usuario cais_pmo_deploy
```

`group_vars/pmo_hml/secrets.yml` está no `.gitignore`. Ansible carrega
automaticamente todos os arquivos de `group_vars/pmo_hml/`.

> Recomendado: após o setup, **rotacione a access key** do `cais_pmo_deploy`
> ou migre para a IAM role da instância (`EC2SSMRole` + policy de ECR).

## Uso

```bash
ansible -m ping pmo_hml
ansible-playbook site.yml --check
ansible-playbook site.yml

# só uma parte
ansible-playbook site.yml --tags aws
ansible-playbook site.yml --tags docker
```

## ECR — push/pull

Depois do playbook, na instância (usuário `ubuntu`):

```bash
aws sts get-caller-identity                       # confirma o perfil
docker pull  <acct>.dkr.ecr.us-east-1.amazonaws.com/cais-pmo-back:homol-xxxx
docker push  <acct>.dkr.ecr.us-east-1.amazonaws.com/cais-pmo-back:homol-xxxx
```

Não é preciso `docker login` — o `amazon-ecr-credential-helper` resolve a
autenticação automaticamente (configurado em `~/.docker/config.json`).

## ⚠️ Formatação do disco

`data_volume_force_format: true` (em `group_vars/pmo_hml/main.yml`) **reformata o
volume a cada execução — apaga tudo em `/data`**. Após o primeiro
provisionamento, mude para `false`.

## Notas

- Device do volume de dados: `/dev/nvme1n1` em instâncias Nitro/NVMe (`t3a.*`).
  O `/dev/sdf` do Terraform é apenas o nome de anexo. Confirme com `lsblk`.
- Backups do fstab em `/etc/fstab.bak-<timestamp>` na instância.
- Após adicionar `ubuntu` ao grupo `docker`, reconecte o SSH.
