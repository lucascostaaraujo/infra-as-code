output "instance_id" {
  description = "ID da instancia EC2"
  value       = aws_instance.cais_interno.id
}

output "instance_state" {
  description = "Estado atual da instancia"
  value       = aws_instance.cais_interno.instance_state
}

output "ami_id" {
  description = "AMI Ubuntu utilizada"
  value       = data.aws_ami.ubuntu.id
}

output "private_ip" {
  description = "IP privado da instancia"
  value       = aws_instance.cais_interno.private_ip
}

output "public_ip" {
  description = "Elastic IP (novo) associado a instancia"
  value       = aws_eip.cais_interno.public_ip
}

output "eip_allocation_id" {
  description = "Allocation ID do Elastic IP criado"
  value       = aws_eip.cais_interno.id
}

output "data_volume_id" {
  description = "ID do volume secundario (20GB) - 1o PV do LVM data_vg"
  value       = aws_ebs_volume.data.id
}

output "additional_data_volume_ids" {
  description = "IDs dos discos extras que estendem o LVM data_vg"
  value       = { for k, v in aws_ebs_volume.data_extra : k => v.id }
}
