provider "aws" {
    region = "ap-south-2"
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
    most_recent = true
    owners      = ["amazon"]

    filter {
        name   = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "my_vpc"
    }
}

# Internet Gateway

resource "aws_internet_gateway" "my_igw" {
    vpc_id = aws_vpc.my_vpc.id
    tags = {
        Name = "my_igw"
    }
}

# Public Subnet
resource "aws_subnet" "my_public_subnet" {
    vpc_id            = aws_vpc.my_vpc.id
    cidr_block        = "10.0.1.0/24"
    availability_zone = "ap-south-2a"
    map_public_ip_on_launch = true
    tags = {
        Name = "my_public_subnet"
    }
}

# Private Subnet
resource "aws_subnet" "my_private_subnet" {
    vpc_id            = aws_vpc.my_vpc.id
    cidr_block        = "10.0.2.0/24"
    availability_zone = "ap-south-2a"
    map_public_ip_on_launch = false
    tags = {
        Name = "my_private_subnet"
    }
}

# Route Table for Public Subnet
resource "aws_route_table" "my_public_route_table" {
    vpc_id = aws_vpc.my_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.my_igw.id
    }
    tags = {
        Name = "my_public_route_table"
    }
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "my_public_route_table_association" {
    subnet_id      = aws_subnet.my_public_subnet.id
    route_table_id = aws_route_table.my_public_route_table.id
}

# Security Group for EC2 Instance
resource "aws_security_group" "my_sg_ec2" {
    name        = "my_sg_ec2"
    description = "Allow SSH and HTTP"
    vpc_id      = aws_vpc.my_vpc.id

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

    tags = {
        Name = "my_sg_ec2"
    }
}

# Launch a Linux EC2 Instance in the Public Subnet
resource "aws_instance" "my_ec2_instance" {
    ami           = data.aws_ami.amazon_linux_2.id # Amazon Linux 2 AMI (HVM), SSD Volume Type
    instance_type = "t3.micro"
    subnet_id     = aws_subnet.my_public_subnet.id
    vpc_security_group_ids = [aws_security_group.my_sg_ec2.id]

    associate_public_ip_address = true

    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd
                systemctl start httpd
                systemctl enable httpd
                echo "<h1>Welcome to my EC2 instance!</h1>" > /var/www/html/index.html
            EOF
    tags = {
        Name = "my_ec2_instance"
    }
}

# Output the public IP of the EC2 instance
output "ec2_instance_public_ip" {
    value = aws_instance.my_ec2_instance.public_ip
}