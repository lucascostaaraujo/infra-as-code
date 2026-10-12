output "instance_id" {
  description = "ID da instancia EC2"
  value       = aws_instance.pmo.id
}

output "instance_state" {
  description = "Estado atual da instancia"
  value       = aws_instance.pmo.instance_state
}

output "ami_id" {
  description = "AMI Ubuntu utilizada"
  value       = data.aws_ami.ubuntu.id
}

output "private_ip" {
  description = "IP privado da instancia"
  value       = aws_instance.pmo.private_ip
}

output "public_ip" {
  description = "Elastic IP (novo) associado a instancia"
  value       = aws_eip.pmo.public_ip
}

output "eip_allocation_id" {
  description = "Allocation ID do Elastic IP criado"
  value       = aws_eip.pmo.id
}

output "pmo_apps_security_group_id" {
  description = "ID do security group PMO_Apps criado"
  value       = aws_security_group.pmo_apps.id
}

output "data_volume_id" {
  description = "ID do volume secundario (10GB)"
  value       = aws_ebs_volume.data.id
}

output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR criados"
  value       = { for k, r in aws_ecr_repository.pmo : k => r.repository_url }
}
