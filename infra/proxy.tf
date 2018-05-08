variable "proxy_ami" {}

resource "aws_security_group" "proxy_sg" {
  name   = "proxy_sg"
  vpc_id = "${aws_vpc.k8s_cluster.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "proxy_server" {
  count                       = 1
  ami                         = "${var.proxy_ami}"
  instance_type               = "t2.micro"
  subnet_id                   = "${aws_subnet.k8s_cluster0.id}"
  vpc_security_group_ids      = ["${aws_security_group.proxy_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  depends_on                  = ["aws_internet_gateway.k8s_cluster"]
  tags {
    Name = "proxy"
  }
}

output "proxy_ep" {
  value = "${aws_instance.proxy_server.private_dns}"
}

