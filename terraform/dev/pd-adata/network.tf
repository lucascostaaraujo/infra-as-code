# ---------------------------------------------------------------------------
# Rede - conta AWS nova, entao a VPC/subnets/IGW sao criados por este stack.
#
# 2 subnets publicas (rota para o IGW) em 2 AZs diferentes: a primaria hospeda
# a EC2, e a segunda existe so para satisfazer o requisito do RDS DB Subnet
# Group (a AWS exige subnets em >= 2 AZs mesmo para instancia Single-AZ).
# Ambas publicas para manter o stack simples (dev); o RDS so fica acessivel de
# fato pela regra do security group (aws_security_group.rds), nao pela rede.
# ---------------------------------------------------------------------------

resource "aws_vpc" "carrier" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = var.vpc_name
  })
}

resource "aws_internet_gateway" "carrier" {
  vpc_id = aws_vpc.carrier.id

  tags = merge(local.common_tags, {
    Name = var.igw_name
  })
}

resource "aws_subnet" "primary" {
  vpc_id                  = aws_vpc.carrier.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-subnet-${var.availability_zone}"
  })
}

resource "aws_subnet" "secondary" {
  vpc_id                  = aws_vpc.carrier.id
  cidr_block              = var.subnet_cidr_secondary
  availability_zone       = var.availability_zone_secondary
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-subnet-${var.availability_zone_secondary}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.carrier.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.carrier.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-public-rt"
  })
}

resource "aws_route_table_association" "primary" {
  subnet_id      = aws_subnet.primary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "secondary" {
  subnet_id      = aws_subnet.secondary.id
  route_table_id = aws_route_table.public.id
}
