# Ansible — Farol Server HML

Provisionamento pós-boot da instância **Farol Server HML** (criada pelo
Terraform em `terraform/hml/farol/`).

## O que o playbook faz

| Role | Ações |
|---|---|
| `common` | `apt update` + `dist-upgrade`, utilitários básicos, reboot se exigido |
| `data_volume` | formata o volume de 10GB, monta em `/data` **via UUID no `/etc/fstab`** (backup do fstab antes), `mount -a` + `daemon-reload`, cria a estrutura de diretórios |
| `docker` | instala Docker Engine + Compose (repo oficial), move o `data-root` para `/data/docker`, habilita no boot (`systemctl enable`), adiciona `ubuntu` ao grupo `docker` |

Estrutura de diretórios criada:

```
/data
├── apps
│   ├── farol-back-homol
│   ├── farol-front-homol
│   └── proxy
└── docker            # data-root do Docker
```

## Pré-requisitos

- Instância já criada e acessível via SSH (usuário `ubuntu`, key pair
  `farol_06072026`).
- Chave privada em `~/.ssh/farol_06072026.pem` (ajuste em `inventory.ini`).
- Ansible 2.15+ na máquina local.

```bash
cd ansible/hml/farol
ansible-galaxy collection install -r requirements.yml
```

## Uso

```bash
ansible -m ping farol_hml          # testa conectividade
ansible-playbook site.yml --check   # dry-run
ansible-playbook site.yml
```

Rodar só uma parte:

```bash
ansible-playbook site.yml --tags docker
ansible-playbook site.yml --tags data_volume
```

## ⚠️ Formatação do disco

`data_volume_force_format: true` (em `group_vars/farol_hml.yml`) faz o volume ser
**reformatado a cada execução — todos os dados em `/data` são apagados**.

Depois do primeiro provisionamento, mude para `false` para execuções
idempotentes (só formata se não houver filesystem).

## Notas

- O device do volume de dados é `/dev/nvme1n1` em instâncias Nitro/NVMe
  (`t3.*`). O `/dev/sdf` do Terraform é apenas o nome de anexo. Confirme com
  `lsblk` e ajuste `data_volume_device` se necessário.
- A montagem no `fstab` usa `nofail,x-systemd.device-timeout=10` — a instância
  sobe mesmo se o volume não estiver presente.
- Backups do fstab ficam em `/etc/fstab.bak-<timestamp>` na instância.
- O `data-root` antigo do Docker é arquivado em
  `/var/lib/docker.migrated-<data>`.
- Após adicionar `ubuntu` ao grupo `docker`, é preciso reconectar o SSH.
