output "instance_id" {
  description = "ID da instancia EC2"
  value       = aws_instance.farol.id
}

output "instance_state" {
  description = "Estado atual da instancia"
  value       = aws_instance.farol.instance_state
}

output "ami_id" {
  description = "AMI Ubuntu utilizada"
  value       = data.aws_ami.ubuntu.id
}

output "private_ip" {
  description = "IP privado da instancia"
  value       = aws_instance.farol.private_ip
}

output "public_ip" {
  description = "Elastic IP associado"
  value       = data.aws_eip.farol.public_ip
}

output "data_volume_id" {
  description = "ID do volume de dados (10GB)"
  value       = aws_ebs_volume.data.id
}
