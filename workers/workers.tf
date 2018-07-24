variable "cluster_name" {
  default = "kubernetes"
}

variable "key_name" {}

variable "vpc_id" {}

data "aws_vpc" "existing" {
  id = "${var.vpc_id}"
}

variable "primary_subnet" {}
variable "secondary_subnet" {}

variable "worker_count" {}
variable "worker_ami" {}

variable "worker_type" {
  default = "m4.4xlarge"
}

variable "worker_disk_size" {
  default = 100
}

provider "aws" {
  version = "1.14.1"
}

resource "aws_iam_role" "worker_role" {
  name = "${var.cluster_name}_worker_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "worker_policy" {
  name = "${var.cluster_name}_worker_policy"
  role = "${aws_iam_role.worker_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:AttachVolume",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:Describe*",
        "ec2:DescribeInstances",
        "ec2:DetachVolume",
        "elasticloadbalancing:*"
        ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:AttachNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DetachNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeInstances",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:AssignPrivateIpAddresses"
     ],
     "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "tag:TagResources",
      "Resource": "*"
    },
    {
      "Action" : [
        "ec2:CreateSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:DeleteSecurityGroup",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}_k8s_worker_profile"
  role = "${aws_iam_role.worker_role.name}"
}

resource "aws_security_group" "worker_sg" {
  name   = "${var.cluster_name}_worker_sg"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  ingress {
    from_port   = 10255
    to_port     = 10255
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

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
    from_port   = 0
    to_port     = 0
    protocol    = "4"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    "Name"    = "heptio-worker"
    "vendor"  = "heptio"
    "cluster" = "${var.cluster_name}"
  }
}

data "local_file" "user_data" {
  filename = "/tmp/kube-workers/worker-bootstrap.sh"
}

resource "aws_launch_configuration" "worker" {
  name_prefix     = "heptio-worker"
  image_id        = "${var.worker_ami}"
  instance_type   = "${var.worker_type}"
  key_name        = "${var.key_name}"
  security_groups = ["${aws_security_group.worker_sg.id}"]
  user_data       = "${data.local_file.user_data.content}"

  #ebs_optimized        = "true"
  iam_instance_profile        = "${aws_iam_instance_profile.worker_profile.name}"
  associate_public_ip_address = "true"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.worker_disk_size}"
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "workers" {
  name                 = "${var.cluster_name}_heptio-worker"
  vpc_zone_identifier  = ["${var.primary_subnet}", "${var.secondary_subnet}"]
  desired_capacity     = "${var.worker_count}"
  max_size             = "${var.worker_count + 1}"
  min_size             = "${var.worker_count}"
  launch_configuration = "${aws_launch_configuration.worker.name}"

  tags = [
    {
      key                 = "Name"
      value               = "heptio-workers"
      propagate_at_launch = true
    },
    {
      key                 = "vendor"
      value               = "heptio"
      propagate_at_launch = true
    },
    {
      key                 = "kubernetes.io/cluster/kubernetes"
      value               = "owned"
      propagate_at_launch = true
    },
    {
      key                 = "cluster"
      value               = "${var.cluster_name}"
      propagate_at_launch = true
    },
  ]
}
