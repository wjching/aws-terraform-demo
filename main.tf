
# Preconfigure aws-profile/credentials with aws-cli on local system beforehand.
provider "aws" {
  region   = "us-east-1"
  profile  = "wjAWS"
}

 #Create VPC
resource "aws_vpc" "demo-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
        Name = "demo"
    }
}

#Create Internet Gateway
resource "aws_internet_gateway" "demo-igw" {
  vpc_id = aws_vpc.demo-vpc.id

  tags = {
    Name = "demo-igw"
  }
}

#Create Route Table
resource "aws_route_table" "demo-route-table" {
  vpc_id = aws_vpc.demo-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo-igw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.demo-igw.id
  }

  tags = {
    Name = "demo-rt"
  }
}

#Create Public Subnet in VPC
resource "aws_subnet" "demo-subnet-public"{
    vpc_id = aws_vpc.demo-vpc.id
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-east-1a"

    tags = {
        Name = "demo-subnet-public"
    }
}

#Create Private Subnet in VPC
resource "aws_subnet" "demo-subnet-private"{
    vpc_id = aws_vpc.demo-vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1b"

    tags = {
        Name = "demo-subnet-private"
    }
}

#Associate Subnet with Route Table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.demo-subnet-public.id
  route_table_id = aws_route_table.demo-route-table.id
}

#Create Security Group

resource "aws_security_group" "allow_web_ssh" {
  name        = "allow_web_ssh_traffic"
  description = "Allow connection between ALB and target instance"
  vpc_id      = aws_vpc.demo-vpc.id

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

  tags = {
    Name = "allow_web"
  }
}

#Create ALB 
resource "aws_lb" "demo" {
  name               = "demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web_ssh.id]
  subnets            = [aws_subnet.demo-subnet-public.id]

  tags = {
    Environment = "demo"
  }
}

#ALB Target Group for HTTP
resource "aws_lb_target_group" "demo_http" {
  name     = "demo-http-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo-vpc.id

}

#ALB Target Group for SSH
resource "aws_lb_target_group" "demo_ssh" {
  name     = "demo-ssh-lb-tg"
  port     = 22
  protocol = "TCP"
  vpc_id   = aws_vpc.demo-vpc.id
}

/* #ALB Forward Action Listener for HTTP
resource "aws_lb_listener" "demo_http" {
  load_balancer_arn = aws_lb.demo.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
}

#ALB Forward Action Listener for SSH
resource "aws_lb_listener" "demo_ssh" {
  load_balancer_arn = aws_lb.demo.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
} */

 #Register EC2 with ALB Target Group HTTP
resource "aws_lb_target_group_attachment" "demo_http" {
  target_group_arn = aws_lb_target_group.demo_http.arn
  target_id        = aws_instance.docker-instance.id
  port             = 80
}

#Register EC2 with ALB Target Group SSH
resource "aws_lb_target_group_attachment" "demo_ssh" {
  target_group_arn = aws_lb_target_group.demo_ssh.arn
  target_id        = aws_instance.docker-instance.id
  port             = 22
} 

#Create network interface with Private IP in Subnet for EC2
resource "aws_network_interface" "docker-server-nic" {
  subnet_id       = aws_subnet.demo-subnet-private.id
  private_ips     = ["10.0.1.10"]
  security_groups = [aws_security_group.allow_web_ssh.id]
}

#Provision Ubuntu Server
resource "aws_instance" "docker-instance"{
    ami = "ami-042e8287309f5df03"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "demo-key"

     network_interface {
      device_index = 0
      network_interface_id = aws_network_interface.docker-server-nic.id
    } 

    #User will inject custom index.html file once the Container is provisioned, otherwise there will be a 403 Forbidden Error
     user_data = <<-EOF
                #!/bin/bash
                curl -fsSL get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                cd /
                sudo mkdir /nginx-content
                sudo docker run -d -p 80:80 -v /nginx-content:/usr/share/nginx/html --name web nginx:1.18.0
                EOF 
    
    tags = {
    Name = "docker-server"
    }
} 