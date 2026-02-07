terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "backup_infrastructure" {
  source = "./modules/backup-infrastructure"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones

  instance_type      = var.instance_type
  ssh_public_key     = var.ssh_public_key
  allowed_ssh_cidrs  = var.allowed_ssh_cidrs

  backup_retention_days = var.backup_retention_days

  tags = var.tags
}
