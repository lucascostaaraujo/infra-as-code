# --- Rede -------------------------------------------------------------
output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "IDs das subnets publicas"
  value       = aws_subnet.public[*].id
}

# --- ECS ----------------------------------------------------------------
output "ecs_cluster_name" {
  description = "Nome do cluster ECS"
  value       = aws_ecs_cluster.this.name
}

# --- ALB ----------------------------------------------------------------
output "alb_dns_name" {
  description = "DNS do ALB"
  value       = aws_lb.this.dns_name
}

output "keycloak_url" {
  description = "URL do Keycloak"
  value       = "${local.scheme}://${var.keycloak_hostname}"
}

output "gatus_url" {
  description = "URL do Gatus"
  value       = "${local.scheme}://${var.gatus_hostname}"
}

output "dns_cnames_to_create" {
  description = "CNAMEs a criar no Registro.br (nome => destino)"
  value = {
    (var.keycloak_hostname) = aws_lb.this.dns_name
    (var.gatus_hostname)    = aws_lb.this.dns_name
  }
}

output "acm_validation_records" {
  description = "CNAMEs de validacao do certificado ACM a criar no Registro.br"
  value = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  }
}

# --- Segredos -------------------------------------------------------------
output "keycloak_admin_password" {
  description = "Senha do admin inicial do Keycloak (sensitive) - `terraform output -raw keycloak_admin_password`"
  value       = random_password.keycloak_admin.result
  sensitive   = true
}

# --- RDS - postgresinfracais -------------------------------------------
output "db_identifier" {
  description = "Identifier da instancia RDS"
  value       = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "Endpoint (host:porta) do RDS"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "Hostname do RDS (sem a porta)"
  value       = aws_db_instance.this.address
}

output "db_password" {
  description = "Senha do master user do RDS (sensitive) - `terraform output -raw db_password`"
  value       = random_password.db.result
  sensitive   = true
}
