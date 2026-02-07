#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Install backup tools
apt-get install -y gnupg awscli git

# Configure PostgreSQL to listen on all interfaces
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf

# Restart PostgreSQL
systemctl restart postgresql

# Create backup directory
mkdir -p /var/backups/databases/postgresql
chown postgres:postgres /var/backups/databases/postgresql

# Set S3 bucket in environment
echo "export BACKUP_S3_BUCKET=${s3_bucket_name}" >> /etc/environment

# Log completion
echo "EC2 initialization completed at $(date)" > /var/log/user-data.log
