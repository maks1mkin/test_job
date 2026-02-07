output "vpc_id" {
  description = "VPC ID"
  value       = module.backup_infrastructure.vpc_id
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.backup_infrastructure.instance_id
}

output "instance_public_ip" {
  description = "EC2 public IP"
  value       = module.backup_infrastructure.instance_public_ip
}

output "instance_private_ip" {
  description = "EC2 private IP"
  value       = module.backup_infrastructure.instance_private_ip
}

output "backup_bucket_name" {
  description = "S3 bucket name for backups"
  value       = module.backup_infrastructure.backup_bucket_name
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh ubuntu@${module.backup_infrastructure.instance_public_ip}"
}
