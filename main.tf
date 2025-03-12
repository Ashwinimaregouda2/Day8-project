provider "aws" {
  region = "ap-southeast-2"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Public Subnets
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-2a"
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-2b"
}

# Associate Public Subnets with Route Table
resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Security Group for EC2 Instances
resource "aws_security_group" "instance_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets           = [aws_subnet.public1.id, aws_subnet.public2.id]

  enable_http2 = true
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Listener for ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"
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

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Launch Template
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt"
  image_id      = "ami-09e143e99e8fa74f9"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<EOF
#!/bin/bash
sudo apt update -y
sudo apt install -y apache2
sudo systemctl start apache2
sudo systemctl enable apache2
echo "Hello from Terraform" > /var/www/html/index.html
EOF
  )
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  desired_capacity     = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.public1.id, aws_subnet.public2.id]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$${aws_launch_template.app_lt.latest_version}"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn]
  health_check_type = "ELB"
}

# S3 Bucket
resource "aws_s3_bucket" "static_content" {
  bucket = "my-static-content-bucket1235"
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
