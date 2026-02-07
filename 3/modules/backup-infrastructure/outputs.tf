output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.database.id
}

output "instance_public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.database.public_ip
}

output "instance_private_ip" {
  description = "EC2 private IP"
  value       = aws_instance.database.private_ip
}

output "backup_bucket_name" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.backups.id
}

output "backup_bucket_arn" {
  description = "S3 backup bucket ARN"
  value       = aws_s3_bucket.backups.arn
}

output "security_group_id" {
  description = "Instance security group ID"
  value       = aws_security_group.instance.id
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.backup.arn
}
