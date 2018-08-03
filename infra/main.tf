variable "cluster_name" {
  default = "kubernetes"
}
variable "key_name" {}
variable "vpc_id" {}

data "aws_vpc" "existing" {
  id = "${var.vpc_id}"
}

variable "primary_subnet_id" {}
variable "secondary_subnet_ids" {
  type = "list"
}

provider "aws" {
  version = "1.14.1"
}

resource "aws_security_group" "cluster_sg" {
  name   = "${var.cluster_name}_cluster_sg"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "TCP"
    #cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = "true"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    "Name"    = "heptio-cluster"
    "vendor"  = "heptio"
    "cluster" = "${var.cluster_name}"
  }
}

output "vpc_cidr" {
  value = "${data.aws_vpc.existing.cidr_block}"
}

