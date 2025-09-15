
terraform {
  required_version = ">= 1.5.0"
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

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project}-vpc" }
}

# Subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "${var.project}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}b"
  tags = { Name = "${var.project}-public-b" }
}

# Internet Gateway & route
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Security groups
resource "aws_security_group" "app_sg" {
  name        = "${var.project}-app-sg"
  description = "App SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project}-db-sg"
  description = "DB SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Postgres from app"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 keypair (expects an existing public key in var.ssh_public_key)
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project}-deployer"
  public_key = var.ssh_public_key
}

# EC2 instances
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true
  tags = { Name = "${var.project}-db" }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_b.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true
  user_data                   = <<-EOT
              #!/bin/bash
              apt-get update -y
              apt-get install -y python3 python3-pip
              EOT
  tags = { Name = "${var.project}-app" }
}

# S3 bucket for artifacts/logs
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-artifacts-${random_id.suffix.hex}"
  force_destroy = true
  tags = { Name = "${var.project}-artifacts" }
}

resource "random_id" "suffix" {
  byte_length = 3
}

output "app_public_ip" { value = aws_instance.app.public_ip }
output "db_public_ip"  { value = aws_instance.db.public_ip }
output "artifacts_bucket" { value = aws_s3_bucket.artifacts.bucket }
