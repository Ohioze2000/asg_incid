#
data "aws_availability_zones" "available" {
  state = "available"
}

# IMPORTANT: Filter the list of available AZs to only the first 'az_count'--
locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

resource "aws_subnet" "my-public-subnet-1" {
    count             = var.az_count
    cidr_block = cidrsubnet(var.vpc_cidr_block, 8, count.index)
    vpc_id = var.vpc_id
    availability_zone   = local.selected_azs[count.index] # Use the filtered list of AZs
    map_public_ip_on_launch = true

    tags = {
        Name = "${var.env_prefix}-pub-subnet-${count.index + 1}"
    }
}

resource "aws_subnet" "my-private-subnet-1" {
    count             = var.az_count # Use az_count here too
    cidr_block = cidrsubnet(var.vpc_cidr_block, 8, count.index + var.az_count)
    vpc_id = var.vpc_id
    availability_zone   = local.selected_azs[count.index] # Use the filtered list of AZs

    tags = {
        Name = "${var.env_prefix}-priv-subnet-${count.index + 1}"
    }
}

resource "aws_internet_gateway" "my-igw" {
    vpc_id = var.vpc_id

    tags = {
        Name = "${var.env_prefix}-igw"
    }
}

resource "aws_route_table" "my-rtb" {
    vpc_id = var.vpc_id
        route {
            cidr_block = "0.0.0.0/0"
            gateway_id = aws_internet_gateway.my-igw.id
        }
    
    tags = {
        Name = "${var.env_prefix}-rtb"
    }
}

resource "aws_route_table_association" "my-rtb-sub-ass" {
    count          = var.az_count
    subnet_id = aws_subnet.my-public-subnet-1[count.index].id
    route_table_id = aws_route_table.my-rtb.id
}

# Elastic IP for NAT Gateway
    resource "aws_eip" "nat" {
    count = var.az_count
    
    tags = { 
      Name = "${var.env_prefix}-nat-eip-${count.index + 1}" 
    }
}

# NAT Gateway
resource "aws_nat_gateway" "my-nat" {
  count         = var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.my-public-subnet-1[count.index].id
  depends_on    = [aws_internet_gateway.my-igw]

  tags = {
    Name = "${var.env_prefix}-nat-gw-${count.index + 1}" 
  }
}

# Private Route Table
resource "aws_route_table" "my-private-rtb" {
  count  = var.az_count
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.my-nat[count.index].id
  }

  tags = {
    Name = "${var.env_prefix}-private-rt-${count.index + 1}" 
  }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.my-private-subnet-1[count.index].id
  route_table_id = aws_route_table.my-private-rtb[count.index].id
}