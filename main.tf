
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
    availability_zone = "us-east-1a"

    tags = {
        Name = "demo-subnet-private"
    }
}

#Provision Internet Gateway for internet access on Public Subnet
resource "aws_internet_gateway" "demo-igw" {
  vpc_id = aws_vpc.demo-vpc.id

  tags = {
    Name = "demo-igw"
  }
}

#Provision NAT Gateway for internet access on Public Subnet
resource "aws_nat_gateway" "gw" {
  allocation_id = aws_eip.natgw.id
  subnet_id     = aws_subnet.demo-subnet-public.id
}

#Create Route Table for Public Subnet
resource "aws_route_table" "demo-route-table-public" {
  vpc_id = aws_vpc.demo-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo-igw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.demo-igw.id
  }

  tags = {
    Name = "demo-rt-public-subnet"
  }
}

#Create Route Table for Private Subnet
resource "aws_route_table" "demo-route-table-private" {
  vpc_id = aws_vpc.demo-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw.id
  }

  tags = {
    Name = "demo-rt-private-subnet"
  }
}

#Associate Public Subnet with Public Route Table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.demo-subnet-public.id
  route_table_id = aws_route_table.demo-route-table-public.id
}

#Associate Public Subnet with Private Route Table

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.demo-subnet-private.id
  route_table_id = aws_route_table.demo-route-table-private.id
}

#Create Security Group

resource "aws_security_group" "allow_web_ssh" {
  name        = "allow_web_ssh_traffic"
  description = "Allow connection between NLB and target instance"
  vpc_id      = aws_vpc.demo-vpc.id

#allow any inbound source for HTTP and SSH Connection from NLB to target instance.
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
    Name = "allow_web_ssh"
  }
}

#Create NLB 
resource "aws_lb" "demo" {
  name               = "demo-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.demo-subnet-public.id]

  tags = {
    Environment = "demo"
  }
}

#NLB Target Group for HTTP
resource "aws_lb_target_group" "demo_http" {
  name     = "demo-http-lb-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.demo-vpc.id

}

#NLB Target Group for SSH
resource "aws_lb_target_group" "demo_ssh" {
  name     = "demo-ssh-lb-tg"
  port     = 22
  protocol = "TCP"
  vpc_id   = aws_vpc.demo-vpc.id
}

#NLB Forward Action Listener for HTTP
resource "aws_lb_listener" "demo_http" {
  load_balancer_arn = aws_lb.demo.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_http.arn
  }
}

#NLB Forward Action Listener for SSH
resource "aws_lb_listener" "demo_ssh" {
  load_balancer_arn = aws_lb.demo.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_ssh.arn
  }
}

 #Register EC2 with NLB Target Group HTTP
resource "aws_lb_target_group_attachment" "demo_http" {
  target_group_arn = aws_lb_target_group.demo_http.arn
  target_id        = aws_instance.docker-instance.id
  port             = 80
}

#Register EC2 with NLB Target Group SSH
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

#EIP for NAT Gateway use
resource "aws_eip" "natgw" {
  vpc      = true
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

    #User will inject custom index.html file once the Container is provisioned, otherwise there will be a 403 Forbidden Error.
    #User to upload index.html file to /nginx-content to preview http content.
    #Below Bash Script will provision Docker Software ontop of Ubuntu Server and provision NGINX Version 1.18.0
    #nginx container directory >> /usr/share/nginx/html, will be mounted to /nginx-content of root folder on ubuntu server
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


