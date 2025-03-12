provider "aws" {
  region = "ap-southeast-2"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Subnets
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

# Security Group
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets           = [aws_subnet.public.id]
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Auto Scaling Group
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt"
  image_id      = "ami-09e143e99e8fa74f9"
  instance_type = "t2.micro"
}

resource "aws_autoscaling_group" "app_asg" {
  desired_capacity     = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.public.id]
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "static_content" {

  bucket = "my-static-content-bucket"

}

# RDS Database
resource "aws_db_instance" "app_db" {
  allocated_storage    = 20
  engine              = "mysql"
  instance_class      = "db.t2.micro"
  multi_az           = true
  db_name            = "appdb"
  username          = "admin"
  password          = "password123"
  skip_final_snapshot = true
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "app_logs" {
  name = "app-log-group"
}

# IAM Role for Jenkins
resource "aws_iam_role" "jenkins_role" {
  name = "jenkins-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Output Load Balancer DNS
output "lb_dns" {
  value = aws_lb.app_lb.dns_name
}
