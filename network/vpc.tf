provider "aws" {
  version = "1.14.1"
	region = "${var.region}"
}

variable "cluster_name" {
  default = "kubernetes"
}

variable "region" {
  default = "us-east-2"
}

variable "cluster_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

resource "aws_vpc" "cluster_vpc" {
  cidr_block           = "${var.cluster_cidr}"
  enable_dns_hostnames = true

  tags {
    Name = "${var.cluster_name}"
  }
}

resource "aws_subnet" "cluster_subnet" {
  count             = "${length(var.availability_zones)}"
  vpc_id            = "${aws_vpc.cluster_vpc.id}"
  cidr_block        = "${cidrsubnet(var.cluster_cidr, 4, count.index)}"
  availability_zone = "${var.availability_zones[count.index]}"

  tags {
    Name = "${var.cluster_name}-${count.index}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.cluster_vpc.id}"

  tags {
    Name = "${var.cluster_name}"
  }
}

resource "aws_route_table_association" "cluster_rt_assoc" {
  count          = "${length(var.availability_zones)}"
  subnet_id      = "${aws_subnet.cluster_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.cluster_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name = "${var.cluster_name}-public"
  }
}

output "vpc_id" {
  value = "${aws_vpc.cluster_vpc.id}"
}

output "primary_subnet_id" {
  value = "${aws_subnet.cluster_subnet.0.id}"
}

output "secondary_subnet_ids" {
  value = "${slice(aws_subnet.cluster_subnet.*.id, 1, length(aws_subnet.cluster_subnet.*.id))}"
}

