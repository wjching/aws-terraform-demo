# aws-terraform-demo
# Terraform Project for deploying Resources in AWS <h1>

The following Terraform Files are used to provision the following Architecture.

![demo-architecture-aws](https://user-images.githubusercontent.com/59917742/113812053-f7ec8800-979f-11eb-9a6d-4971e02c68b9.JPG)


# It Spins up the list of Services: <h2>

1. VPC (Virtual Private Cloud)
2. Subnets within VPC
3. Route Table (Provide Routing between Internet Gateway and ALB, ALB to EC2 Instance)
4. Security Groups (To allow specific TCP service ports to transmit and recieve its connection)
5. EIP (Elastic IP)
6. NLB (Network Load Balancer), for listening TCP Port 22 and Port 80
7. Internet Gateway (Provide Internet access to and from public subnet)
8. NAT Gateway (Provide Internet access to and afrom private subnet)
9. EC2 Instances (bootstraped with docker to provision and configure ngix image)

Be sure to always run the following command before executing this .tf file:
$terraform init 

