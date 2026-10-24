# network.tf
# The VPC and its public-subnet plumbing. On purpose there are NO private
# subnets and NO NAT gateway here — a NAT would add ~$32/month, and this
# stack doesn't need the isolation yet. The trade-off is that ECS tasks run
# in public subnets with a public IP, which is fine because the task SG
# only accepts traffic from the ALB SG.
#
# Topology:
#
#   VPC 10.0.0.0/16
#   ├── IGW
#   ├── subnet public-0  10.0.0.0/24  (AZ a)
#   ├── subnet public-1  10.0.1.0/24  (AZ b)
#   └── route table      0.0.0.0/0 -> IGW   (attached to both subnets)

# Pick whatever AZs AWS says are currently healthy. We only need two of them
# (ALBs want >=2, RDS subnet groups want >=2).
data "aws_availability_zones" "available" {
  state = "available"
}

# The VPC itself. /16 is way more addresses than we'll ever use, but it's
# the AWS default and leaves room to carve out private subnets later without
# renumbering anything.
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true # Needed for instances to resolve DNS at all.
  enable_dns_hostnames = true # Needed for RDS's public DNS endpoint to work.

  tags = {
    Name = "${var.project}-vpc"
  }
}

# The door to the internet. Nothing public works without this.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-igw"
  }
}

# Two public subnets, one per AZ. `map_public_ip_on_launch` means any ENI
# that lands here (ECS tasks, RDS) auto-gets a public IP — important because
# we don't have a NAT, so this is the only way out to ECR/OpenAI.
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${count.index}"
  }
}

# Single shared route table: default route goes out the IGW. Dead simple.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-public-rt"
  }
}

# Glue the route table to each subnet. Without this the subnets technically
# fall back to the default (main) route table, which has no IGW route.
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
