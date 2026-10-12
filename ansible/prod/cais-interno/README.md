# Ansible — CAIS-Interno Server PRD

Provisionamento pós-boot da instância **CAIS-Interno Server - PRD** (criada pelo
Terraform em `terraform/prod/cais-interno/`). Espelha `ansible/hml/cais-interno/`,
mudando apenas os nomes das pastas criadas em `/data/apps` (sufixo `-prod`).

## O que o playbook faz

| Role | Ações |
|---|---|
| `common` | `apt update` + `dist-upgrade`, utilitários básicos, reboot se exigido |
| `data_volume` | monta o disco de 20GB via **LVM** (PV → VG `data_vg` → LV `data_lv` a 100% do VG), formata em `ext4`, monta em `/data` **via UUID no `/etc/fstab`** (backup do fstab antes), `mount -a` + `daemon-reload`, cria a estrutura de diretórios |
| `docker` | instala Docker Engine + Compose (repo oficial), move o `data-root` do Docker para `/data/docker` **e o root do containerd para `/data/containerd`** (imagens/layers), habilita no boot, adiciona `ubuntu` ao grupo `docker` |
| `aws_cli` | instala AWS CLI v2, grava `~/.aws/{config,credentials}` e `~/.docker/config.json` (credential helper do ECR) para **`ubuntu` e `root`**, e valida a autenticação/`docker pull` como `root` |

Estrutura de diretórios criada:

```
/data                 # LV data_vg/data_lv (ext4), montado por UUID
├── apps
│   ├── farol-front-prod
│   ├── farol-back-prod
│   ├── proxy
│   ├── pmo-front-prod
│   └── pmo-back-prod
├── containerd        # root do containerd (imagens/layers/snapshots)
└── docker            # data-root do Docker (volumes, buildkit, rede)
```

## Armazenamento do Docker 100% no disco de 20GB

O `docker-ce` do apt usa o **containerd do sistema** e, no Docker ≥ 28, o
_containerd image store_ é o padrão — as imagens ficam em `/var/lib/containerd`,
**fora** do `data-root` do Docker. Por isso a role `docker` move **os dois**:

| Componente | De | Para |
|---|---|---|
| `data-root` do Docker (volumes, buildkit, rede, logs) | `/var/lib/docker` | `/data/docker` (via `/etc/docker/daemon.json`) |
| `root` do containerd (content store + snapshots das imagens) | `/var/lib/containerd` | `/data/containerd` (via `root =` em `/etc/containerd/config.toml`) |

`state` do containerd (runtime) continua em `/run/containerd` (tmpfs, sem disco).
Marcador `/data/containerd/.relocated` torna a migração idempotente.

> Após a migração, sobram cópias antigas no disco raiz:
> `/var/lib/docker.migrated-*` e `/var/lib/containerd.migrated-*`. Confira com
> `du -sh /var/lib/docker* /var/lib/containerd*` e remova-as manualmente para
> liberar o `/`.

## Ampliar o `/data` no futuro (LVM)

O volume de 20GB é um Physical Volume do VG `data_vg`. Para aumentar o
armazenamento **sem downtime e sem recriar nada**:

1. **Terraform** (`terraform/prod/cais-interno`): adicione uma entrada em
   `additional_data_volumes`, ex.:
   ```hcl
   additional_data_volumes = {
     g = { size = 50 }   # anexado em /dev/sdg
   }
   ```
   `terraform apply`.
2. Na instância, descubra o device novo: `lsblk` (ex.: `/dev/nvme2n1`).
3. Acrescente esse device em `data_volume_devices`
   (`group_vars/cais_interno_prod/main.yml`), mantendo
   `data_volume_force_format: false`.
4. `ansible-playbook site.yml --tags data_volume`
   → `pvcreate` + `vgextend` + `lvextend -l +100%FREE` + `resize2fs` online.

Como o LVM identifica os PVs pela assinatura no disco (não pelo nome do device),
mudanças de `/dev/nvmeXn1` entre reboots não afetam a montagem.

## Pré-requisitos

- Instância criada e acessível via SSH (usuário `ubuntu`, key pair
  `farol_06072026`).
- Chave privada em `~/farol_06072026.pem` (ajuste em `inventory.ini`).
- `ansible_host` em `inventory.ini` = Elastic IP novo da instância:
  ```bash
  terraform -chdir=../../../terraform/prod/cais-interno output -raw public_ip
  ```
- Ansible 2.15+ e as collections:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

## Credenciais (fora do Git)

O secret **não** é versionado. Antes do primeiro run:

```bash
cp group_vars/cais_interno_prod/secrets.yml.example group_vars/cais_interno_prod/secrets.yml
# editar group_vars/cais_interno_prod/secrets.yml com a access key / secret do usuario de deploy
```

`group_vars/cais_interno_prod/secrets.yml` está no `.gitignore`. Ansible carrega
automaticamente todos os arquivos de `group_vars/cais_interno_prod/`.

> Recomendado: após o setup, **rotacione a access key** de deploy ou migre para a
> IAM role da instância (`EC2SSMRole` + policy de ECR).

## Deploy via SSM como root

O pipeline de deploy desta aplicação usa **SSM (Session Manager)**, não SSH, e
roda os comandos de deploy como **`root`**. Por isso a role `aws_cli` grava
`~/.aws` e `~/.docker/config.json` tanto para `ubuntu` quanto para `root`
(`aws_cli_targets` em `roles/aws_cli/defaults/main.yml`), e a validação de
autenticação no ECR (`aws ecr get-login-password`) roda como `root` — não mais
como `ubuntu`, refletindo o usuário real usado pelo pipeline.

Para validar de fato um `docker pull` (não só a autenticação) durante o
playbook, defina `aws_ecr_smoke_test_repo` (ex. `-e aws_ecr_smoke_test_repo=farol-back:latest`)
apontando para um repositório/tag que já exista no ECR. Por padrão fica vazio e
o teste é pulado.

## Uso

```bash
ansible -m ping cais_interno_prod
ansible-playbook site.yml --check
ansible-playbook site.yml

# só uma parte
ansible-playbook site.yml --tags aws
ansible-playbook site.yml --tags docker
```

## ⚠️ Formatação do disco

`data_volume_force_format: true` (nos defaults do role `data_volume`) **reformata o
volume a cada execução — apaga tudo em `/data`**. Em
`group_vars/cais_interno_prod/main.yml` ele já vem como `false`; mantenha `false`
após o primeiro provisionamento.

## Notas

- Device do volume de dados: `/dev/nvme1n1` em instâncias Nitro/NVMe (`t3a.*`).
  O `/dev/sdf` do Terraform é apenas o nome de anexo. Confirme com `lsblk`.
- Backups do fstab em `/etc/fstab.bak-<timestamp>` na instância.
- Após adicionar `ubuntu` ao grupo `docker`, reconecte o SSH.
- Todos os repositórios ECR já existem (criados pelos stacks `farol` / `pmo`);
  este playbook apenas configura o acesso, não cria repositórios.
