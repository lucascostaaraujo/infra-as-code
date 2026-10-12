# cais-infra

Keycloak + Gatus em ECS Fargate (on-demand), com ALB e RDS Postgres, em `us-east-1`
(profile AWS `aws-infra`, conta nova — a VPC é criada por este stack).

| Recurso | Detalhe |
|---|---|
| Rede | VPC `10.40.0.0/16`, 2 subnets públicas (1a/1b), IGW, sem NAT |
| ECS | Cluster `cais-infra`, capacity provider `FARGATE` (sem Spot) |
| Keycloak | 2 vCPU / 4 GB, 20 GB de disco efêmero (padrão Fargate) |
| Gatus | 1 vCPU / 2 GB, 20 GB de disco efêmero; `config.yaml` gravado por container init |
| ALB | `cais-infra-alb`; Keycloak em 80/443, Gatus por host header (`gatus_hostname`) ou porta `gatus_listener_port` (8080) |
| RDS | `postgresinfracais`, Postgres 17, `db.t4g.small`, gp3 100 GB, database `keycloak` (vazio) |
| Segredos | Secrets Manager: senha do RDS e do admin do Keycloak, injetadas via ECS `secrets` |

## Uso

```
terraform init
terraform plan -out tfplan
terraform apply tfplan
terraform output -raw keycloak_admin_password
```

## Domínio (Registro.br) e HTTPS em 2 fases

Hosts: `auth.institutocais.org.br` (Keycloak) e `gatus.institutocais.org.br` (Gatus). O DNS
fica no Registro.br, então os CNAMEs são manuais. O ALB roteia por host header; qualquer
outro host recebe 404.

1. `terraform apply` com `enable_https = false` (padrão): sobe tudo em HTTP:80 e cria o
   certificado ACM (ainda `PENDING_VALIDATION`).
2. No Registro.br crie:
   - os CNAMEs de validação do ACM (`terraform output acm_validation_records`);
   - `auth` e `gatus` apontando para o ALB (`terraform output dns_cnames_to_create`).
3. Quando o certificado estiver `ISSUED`, rode `terraform apply -var enable_https=true`
   (ou mude o default): cria o listener 443 e o 80 passa a redirecionar para HTTPS.

Enquanto estiver em HTTP o Keycloak trafega credenciais sem TLS — não use em produção
nessa fase. O Keycloak recebe `KC_HOSTNAME` com o esquema atual (`http`/`https`).

## Pontos de atenção

- Disco de 20 GB é o padrão do Fargate (o campo `ephemeral_storage` aceita 21–200), então o
  bloco só é declarado se `ephemeral_storage_gib > 20`. O disco é efêmero: os dados do
  Keycloak ficam no RDS.
- Keycloak com `desired_count > 1` exige configurar cache distribuído (JGroups) — não
  incluído; mantenha 1 task.
- RDS `publicly_accessible = true` como no `dev/pd-adata`, mas o SG só libera as tasks ECS
  e os CIDRs de `db_allowed_cidr_blocks` (vazio por padrão).
- `deletion_protection = true` e final snapshot ligados: antes de `terraform destroy`,
  desative a proteção.
- Tasks em subnet pública com IP público (evita o custo do NAT); o SG só aceita entrada do ALB.
