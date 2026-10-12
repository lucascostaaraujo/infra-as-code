# Ansible — P&D-Adata Server DEV

Provisionamento pós-boot da instância **P&D-Adata Server - DEV** (criada pelo
Terraform em `terraform/dev/pd-adata/`). Espelha `ansible/prod/cais-interno/`,
mudando o tamanho do disco de dados e os nomes das pastas criadas em
`/data/apps`.

## O que o playbook faz

| Role | Ações |
|---|---|
| `common` | `apt update` + `dist-upgrade`, utilitários básicos, reboot se exigido |
| `data_volume` | monta o disco de 90GB via **LVM** (PV → VG `data_vg` → LV `data_lv` a 100% do VG), formata em `ext4`, monta em `/data` **via UUID no `/etc/fstab`** (backup do fstab antes), `mount -a` + `daemon-reload`, cria a estrutura de diretórios |
| `docker` | instala Docker Engine + Compose (repo oficial), move o `data-root` do Docker para `/data/docker` **e o root do containerd para `/data/containerd`** (imagens/layers), habilita no boot, adiciona `ubuntu` ao grupo `docker` |
| `aws_cli` | instala AWS CLI v2, grava `~/.aws/{config,credentials}` (perfil `pd_adata_deploy`), instala `amazon-ecr-credential-helper` e configura `~/.docker/config.json` para push/pull no ECR sem `docker login` manual |

Estrutura de diretórios criada:

```
/data                    # LV data_vg/data_lv (ext4), montado por UUID
├── apps
│   ├── proxy
│   ├── pd-adata-front-homol
│   ├── pd-adata-back-homol
│   ├── pd-adata-front-dev
│   └── pd-adata-back-dev
├── containerd            # root do containerd (imagens/layers/snapshots)
└── docker                # data-root do Docker (volumes, buildkit, rede)
```

## Armazenamento do Docker 100% no disco de 90GB

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

> **Sem handlers de restart**: diferente de versões antigas desta role, o
> (re)start do Docker/containerd acontece só uma vez, na Seção 4 da task
> (`roles/docker/tasks/main.yml`), depois que `daemon.json`/`config.toml` já
> foram escritos. Restarts extras em sequência (via `notify`/handler) já
> causaram `start-limit-hit` do systemd em outra instância — por isso essa
> role não usa handlers.

## Ampliar o `/data` no futuro (LVM)

O volume de 90GB é um Physical Volume do VG `data_vg`. Para aumentar o
armazenamento **sem downtime e sem recriar nada**:

1. **Terraform** (`terraform/dev/pd-adata`): adicione uma entrada em
   `additional_data_volumes`, ex.:
   ```hcl
   additional_data_volumes = {
     g = { size = 50 }   # anexado em /dev/sdg
   }
   ```
   `terraform apply`.
2. Na instância, descubra o device novo: `lsblk` (ex.: `/dev/nvme2n1`).
3. Acrescente esse device em `data_volume_devices`
   (`group_vars/pd_adata_dev/main.yml`), mantendo
   `data_volume_force_format: false`.
4. `ansible-playbook site.yml --tags data_volume`
   → `pvcreate` + `vgextend` + `lvextend -l +100%FREE` + `resize2fs` online.

Como o LVM identifica os PVs pela assinatura no disco (não pelo nome do device),
mudanças de `/dev/nvmeXn1` entre reboots não afetam a montagem.

## Pré-requisitos

- Instância criada e acessível via SSH (usuário `ubuntu`, key pair
  `carrier_23092026` — gerada pelo Terraform em `terraform/dev/pd-adata/`).
- Chave privada: copie `terraform/dev/pd-adata/carrier_23092026.pem` para
  `~/carrier_23092026.pem` (caminho referenciado em `inventory.ini`) e ajuste a
  permissão:
  ```bash
  chmod 600 ~/carrier_23092026.pem
  ```
- `ansible_host` em `inventory.ini` = Elastic IP novo da instância:
  ```bash
  terraform -chdir=../../../terraform/dev/pd-adata output -raw public_ip
  ```
- Ansible 2.15+ e as collections:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

## Credenciais (fora do Git)

O secret **não** é versionado. Antes do primeiro run:

```bash
cp group_vars/pd_adata_dev/secrets.yml.example group_vars/pd_adata_dev/secrets.yml
# editar group_vars/pd_adata_dev/secrets.yml com a access key / secret do usuario de deploy
```

`group_vars/pd_adata_dev/secrets.yml` está no `.gitignore`. Ansible carrega
automaticamente todos os arquivos de `group_vars/pd_adata_dev/`.

> Recomendado: após o setup, **rotacione a access key** de deploy ou migre para a
> IAM role da instância (`EC2SSMRole` + policy de ECR).

## Uso

```bash
ansible -m ping pd_adata_dev
ansible-playbook site.yml --check
ansible-playbook site.yml

# só uma parte
ansible-playbook site.yml --tags aws
ansible-playbook site.yml --tags docker
```

> `--check` (dry-run) costuma falhar na role `data_volume`: os módulos de LVM
> (`lvg`/`lvol`) não conseguem simular corretamente uma cadeia de operações
> dependentes em modo de simulação. Isso é uma limitação conhecida desses
> módulos, não um problema de configuração — rode sem `--check` quando chegar
> nesse ponto.

## ⚠️ Formatação do disco

`data_volume_force_format: true` (nos defaults do role `data_volume`) **reformata o
volume a cada execução — apaga tudo em `/data`**. Em
`group_vars/pd_adata_dev/main.yml` ele já vem como `false`; mantenha `false`
após o primeiro provisionamento.

## Notas

- Device do volume de dados: `/dev/nvme1n1` em instâncias Nitro/NVMe (`t3a.*`).
  O `/dev/sdf` do Terraform é apenas o nome de anexo. Confirme com `lsblk`.
- Backups do fstab em `/etc/fstab.bak-<timestamp>` na instância.
- Após adicionar `ubuntu` ao grupo `docker`, reconecte o SSH.
- Os repositórios ECR (`pd-adata-front`, `pd-adata-back`) já existem (criados
  pelo Terraform em `terraform/dev/pd-adata/`); este playbook apenas configura
  o acesso, não cria repositórios.
