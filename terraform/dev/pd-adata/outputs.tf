# --- Rede -------------------------------------------------------------
output "vpc_id" {
  description = "ID da VPC carrier"
  value       = aws_vpc.carrier.id
}

output "subnet_id_primary" {
  description = "ID da subnet primaria (EC2)"
  value       = aws_subnet.primary.id
}

output "subnet_id_secondary" {
  description = "ID da subnet secundaria (so DB Subnet Group)"
  value       = aws_subnet.secondary.id
}

output "db_security_group_id" {
  description = "ID do security group do RDS"
  value       = aws_security_group.rds.id
}

# --- EC2 ----------------------------------------------------------------
output "instance_id" {
  description = "ID da instancia EC2"
  value       = aws_instance.pd_adata.id
}

output "instance_state" {
  description = "Estado atual da instancia"
  value       = aws_instance.pd_adata.instance_state
}

output "ami_id" {
  description = "AMI Ubuntu utilizada"
  value       = data.aws_ami.ubuntu.id
}

output "private_ip" {
  description = "IP privado da instancia"
  value       = aws_instance.pd_adata.private_ip
}

output "public_ip" {
  description = "Elastic IP (novo) associado a instancia"
  value       = aws_eip.pd_adata.public_ip
}

output "eip_allocation_id" {
  description = "Allocation ID do Elastic IP criado"
  value       = aws_eip.pd_adata.id
}

output "data_volume_id" {
  description = "ID do volume secundario (90GB) montado em /data"
  value       = aws_ebs_volume.data.id
}

output "additional_data_volume_ids" {
  description = "IDs dos discos extras que estendem o /data"
  value       = { for k, v in aws_ebs_volume.data_extra : k => v.id }
}

# --- Key pair -------------------------------------------------------------
output "key_pair_name" {
  description = "Nome da key pair criada (carrier_23092026)"
  value       = aws_key_pair.carrier.key_name
}

output "key_pair_private_key_path" {
  description = "Caminho local do .pem gerado (gitignored)"
  value       = local_sensitive_file.carrier_pem.filename
}

# --- ECR --------------------------------------------------------------
output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR criados"
  value       = { for k, v in aws_ecr_repository.pd_adata : k => v.repository_url }
}

# --- S3 -----------------------------------------------------------------
output "s3_bucket_names" {
  description = "Nomes dos buckets S3 criados"
  value       = { for k, v in aws_s3_bucket.pd_adata : k => v.id }
}

output "s3_bucket_arns" {
  description = "ARNs dos buckets S3 criados"
  value       = { for k, v in aws_s3_bucket.pd_adata : k => v.arn }
}

# --- RDS - postgrescarrier foi excluida; ver outputs db2_* (postgresadata) -

# --- AutoOnOff --------------------------------------------------------
output "autooff_lambda_function_name" {
  description = "Nome da Lambda de liga/desliga por tag (autoOnOff=true)"
  value       = aws_lambda_function.autooff.function_name
}

output "autooff_schedule_start" {
  description = "Cron do schedule de start (07:00 BRT, seg-sex)"
  value       = aws_scheduler_schedule.autooff_start.schedule_expression
}

output "autooff_schedule_stop" {
  description = "Cron do schedule de stop (19:00 BRT, seg-sex)"
  value       = aws_scheduler_schedule.autooff_stop.schedule_expression
}

# --- RDS - postgresadata ----------------------------------------------
output "db2_identifier" {
  description = "Identifier da instancia RDS postgresadata"
  value       = aws_db_instance.postgresadata.id
}

output "db2_endpoint" {
  description = "Endpoint (host:porta) da postgresadata"
  value       = aws_db_instance.postgresadata.endpoint
}

output "db2_address" {
  description = "Hostname da postgresadata (sem a porta)"
  value       = aws_db_instance.postgresadata.address
}

output "db2_password" {
  description = "Senha do master user da postgresadata (sensitive) - `terraform output -raw db2_password`"
  value       = random_password.postgresadata.result
  sensitive   = true
}
