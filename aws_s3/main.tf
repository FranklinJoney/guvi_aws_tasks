provider "aws" {
    region = "ap-south-2"
}

# Create S3 Bucket
resource "aws_s3_bucket" "my_bucket" {
    bucket = "franklin-public-bucket-${random_id.suffix.hex}"
    force_destroy = true

    tags = {
        Name        = "my_bucket"
    }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# Block all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "my_bucket_public_access_block" {
    bucket = aws_s3_bucket.my_bucket.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

# Cloudwatch Log Group for S3 Bucket
resource "aws_cloudwatch_log_group" "my_bucket_log_group" {
    name              = "/aws/s3/my_bucket_log_group"
    retention_in_days = 14
}

# --- VPC ---
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "MyVPC" }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags   = { Name = "MyIGW" }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-2a"
  map_public_ip_on_launch = true
  tags = { Name = "PublicSubnetA" }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "ap-south-2b"
  map_public_ip_on_launch = true
  tags = { Name = "PublicSubnetB" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
  tags = { Name = "PublicRouteTable" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Security Group ---
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.my_vpc.id
  name   = "EC2SecurityGroup"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = { Name = "EC2SG" }
}

# --- AMI Lookup ---
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --- EC2 Instances ---
resource "aws_instance" "web1" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx
              systemctl enable nginx
              systemctl start nginx
              echo "Hello from Web1" > /usr/share/nginx/html/index.html
              EOF

  tags = { Name = "WebServer1" }
}

resource "aws_instance" "web2" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnet_b.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx
              systemctl enable nginx
              systemctl start nginx
              echo "Hello from Web2" > /usr/share/nginx/html/index.html
              EOF

  tags = { Name = "WebServer2" }
}

# AWS LoadBalancer
resource "aws_lb" "my_load_balancer" {
    name               = "my-load-balancer"
    internal           = false
    load_balancer_type = "application"
    security_groups    = [aws_security_group.ec2_sg.id]
    subnets            = [
        aws_subnet.public_subnet_a.id,
        aws_subnet.public_subnet_b.id
    ]

    tags = {
        Name = "my_load_balancer"
    }
}

resource "aws_lb_target_group" "tg" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
}

resource "aws_lb_target_group_attachment" "web1_attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web2_attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Outputs
output "s3_bucket_name" {
    value = aws_s3_bucket.my_bucket.bucket
}

output "load_balancer_dns_name" {
    value = aws_lb.my_load_balancer.dns_name
}

