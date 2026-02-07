variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "Allowed CIDR blocks for SSH"
  type        = list(string)
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
