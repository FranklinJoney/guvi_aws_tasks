provider "aws"{
    region = "ap-south-2"
}

# AWS AMI DATA SOURCE
data "aws_ami" "amazon_linux" {
    most_recent = true
    owners      = ["amazon"] # Canonical

    filter {
        name   = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

data "aws_ami" "windows" {
    most_recent = true
    owners      = ["amazon"] # Canonical

    filter {
        name   = "name"
        values = ["Windows_Server-2019-English-Full-Base-*"]
    }
}

# Security Groups
resource "aws_security_group" "web_sg_1"{
    name        = "web_sg_1"
    description = "Allow inbound traffic for web server"
    vpc_id      = aws_vpc.main.id

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 3389
        to_port     = 3389
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

# Linux EC2 Instance
resource "aws_instance" "linux_ec2" {
    ami           = data.aws_ami.amazon_linux.id
    instance_type = "t3.micro"
    security_groups = [aws_security_group.web_sg_1.name]
    key_name      = aws_key_pair.deployer.key_name

    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd
                systemctl start httpd
                systemctl enable httpd
                echo "<h1>Welcome to Linux EC2 Instance</h1>" > /var/www/html/index.html
            EOF

    tags = { Name = "Linux-EC2" }
}

# Windows EC2 Instance
resource "aws_instance" "windows_ec2" {
    ami           = data.aws_ami.windows.id
    instance_type = "t3.micro"
    security_groups = [aws_security_group.web_sg_1.name]
    key_name      = aws_key_pair.deployer.key_name

    user_data = <<-EOF
                <powershell>
                Install-WindowsFeature -Name Web-Server -IncludeManagementTools
                New-Item -Path "C:\\inetpub\\wwwroot\\index.html" -ItemType File -Value "<h1>Welcome to Windows EC2 Instance</h1>"
                </powershell>
            EOF

    tags = { Name = "Windows-EC2" }
}

# EBS Volume 5 GB
resource "aws_ebs_volume" "web_volume" {
    availability_zone = aws_instance.linux_ec2.availability_zone
    size              = 5
    tags = {
        Name = "Web-Volume"
    }
}

# Attach EBS Volume to Linux EC2 Instance
resource "aws_volume_attachment" "web_volume_attachment" {
    device_name = "/dev/sdh"
    volume_id   = aws_ebs_volume.web_volume.id
    instance_id = aws_instance.linux_ec2.id
}

# Attach EBS Volume to Windows EC2 Instance
resource "aws_volume_attachment" "web_volume_attachment_windows" {
    device_name = "xvdf"
    volume_id   = aws_ebs_volume.web_volume.id
    instance_id = aws_instance.windows_ec2.id
}

# Snapshot of EBS Volume
resource "aws_ebs_snapshot" "web_volume_snapshot" {
    volume_id = aws_ebs_volume.web_volume.id
    tags = {
        Name = "Web-Volume-Snapshot"
    }
}

# New Volume from Snapshot 
resource "aws_ebs_volume" "web_volume_from_snapshot" {
    availability_zone = aws_instance.linux_ec2.availability_zone
    snapshot_id       = aws_ebs_snapshot.web_volume_snapshot.id
    tags = {
        Name = "Web-Volume-From-Snapshot"
    }
}