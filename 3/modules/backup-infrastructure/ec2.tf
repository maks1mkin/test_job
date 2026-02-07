resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.environment}-key"
  public_key = var.ssh_public_key

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-key"
    }
  )
}

resource "aws_instance" "database" {
  ami           = "ami-003b64319cbf4db2"
  instance_type = var.instance_type
  
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = true
  
  key_name             = aws_key_pair.main.key_name
  iam_instance_profile = aws_iam_instance_profile.backup.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    s3_bucket_name = aws_s3_bucket.backups.id
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-db"
      Role = "database"
    }
  )
}
