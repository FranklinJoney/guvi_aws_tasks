#############################
# Providers
#############################
provider "aws" {
  region = "ap-south-1" # Mumbai
}

provider "aws" {
  alias  = "south_2"
  region = "ap-south-2" # Hyderabad
}

#############################
# Mumbai VPC + Public Subnet + IGW + Route
#############################
resource "aws_vpc" "mumbai_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "mumbai-custom-vpc" }
}

resource "aws_subnet" "mumbai_public_subnet" {
  vpc_id                  = aws_vpc.mumbai_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"
  tags = { Name = "mumbai-public-subnet" }
}

resource "aws_internet_gateway" "mumbai_igw" {
  vpc_id = aws_vpc.mumbai_vpc.id
  tags = { Name = "mumbai-igw" }
}

resource "aws_route_table" "mumbai_public_rt" {
  vpc_id = aws_vpc.mumbai_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mumbai_igw.id
  }
  tags = { Name = "mumbai-public-rt" }
}

resource "aws_route_table_association" "mumbai_public_rta" {
  subnet_id      = aws_subnet.mumbai_public_subnet.id
  route_table_id = aws_route_table.mumbai_public_rt.id
}

#############################
# Hyderabad VPC + Public Subnet + IGW + Route (uses alias provider)
#############################
resource "aws_vpc" "hyd_vpc" {
  provider = aws.south_2
  cidr_block = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "hyd-custom-vpc" }
}

resource "aws_subnet" "hyd_public_subnet" {
  provider                = aws.south_2
  vpc_id                  = aws_vpc.hyd_vpc.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-2a"
  tags = { Name = "hyd-public-subnet" }
}

resource "aws_internet_gateway" "hyd_igw" {
  provider = aws.south_2
  vpc_id   = aws_vpc.hyd_vpc.id
  tags = { Name = "hyd-igw" }
}

resource "aws_route_table" "hyd_public_rt" {
  provider = aws.south_2
  vpc_id = aws_vpc.hyd_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hyd_igw.id
  }
  tags = { Name = "hyd-public-rt" }
}

resource "aws_route_table_association" "hyd_public_rta" {
  provider       = aws.south_2
  subnet_id      = aws_subnet.hyd_public_subnet.id
  route_table_id = aws_route_table.hyd_public_rt.id
}

#############################
# AMI lookups (latest Amazon Linux 2)
#############################
data "aws_ami" "mumbai_ami" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ami" "hyd_ami" {
  provider    = aws.south_2
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#############################
# Security Groups (allow HTTP only)
#############################
resource "aws_security_group" "mumbai_sg" {
  vpc_id = aws_vpc.mumbai_vpc.id
  name   = "mumbai-nginx-sg"
  description = "Allow HTTP from anywhere"

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

  tags = { Name = "mumbai-nginx-sg" }
}

resource "aws_security_group" "hyd_sg" {
  provider = aws.south_2
  vpc_id   = aws_vpc.hyd_vpc.id
  name     = "hyd-nginx-sg"
  description = "Allow HTTP from anywhere"

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

  tags = { Name = "hyd-nginx-sg" }
}

#############################
# EC2 Instances (Nginx via user_data)
#############################
resource "aws_instance" "mumbai_instance" {
  ami                    = data.aws_ami.mumbai_ami.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.mumbai_public_subnet.id
  vpc_security_group_ids = [aws_security_group.mumbai_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras enable nginx1
              yum install -y nginx
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = { Name = "Mumbai-Nginx" }
}

resource "aws_instance" "hyd_instance" {
  provider               = aws.south_2
  ami                    = data.aws_ami.hyd_ami.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.hyd_public_subnet.id
  vpc_security_group_ids = [aws_security_group.hyd_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras enable nginx1
              yum install -y nginx
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = { Name = "Hyderabad-Nginx" }
}

#############################
# Outputs
#############################
output "mumbai_instance_public_ip" {
  value = aws_instance.mumbai_instance.public_ip
}

output "hyd_instance_public_ip" {
  value = aws_instance.hyd_instance.public_ip
}

output "mumbai_subnet_id" {
  value = aws_subnet.mumbai_public_subnet.id
}

output "hyd_subnet_id" {
  value = aws_subnet.hyd_public_subnet.id
}

output "mumbai_sg_id" {
  value = aws_security_group.mumbai_sg.id
}

output "hyd_sg_id" {
  value = aws_security_group.hyd_sg.id
}