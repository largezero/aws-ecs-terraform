provider "aws" {
  profile = "default"
  region = "ap-northeast-2"
}

locals {
  svc_nm = "dy"
  creator = "dyheo"
  group = "t-dyheo"

  pem_file = "dyheo-histech"

  ## EC2 를 만들기 위한 로컬변수 선언
  ami = "ami-0e4a9ad2eb120e054" ## AMAZON LINUX 2
  instance_type = "t2.micro"
}

## TAG NAME 으로 vpc id 를 가져온다.
data "aws_vpc" "this" {
  filter {
    name = "tag:Name"
    values = ["${local.svc_nm}-vpc"]
  }
}

## TAG NAME 으로 security group 을 가져온다.
data "aws_security_group" "sg-core" {
  vpc_id = "${data.aws_vpc.this.id}"
  filter {
    name = "tag:Name"
    values = ["${local.svc_nm}-sg-core"]
  }
}

## TAG NAME 으로 subnet 을 가져온다.
data "aws_subnet_ids" "public" {
  vpc_id = "${data.aws_vpc.this.id}"
  filter {
    name = "tag:Name"
    values = ["${local.svc_nm}-sb-public-*"]
  }
}

data "aws_subnet" "public" {
  for_each = data.aws_subnet_ids.public.ids
  id = each.value
}

data "aws_iam_policy_document" "assume_by_ecs" {
  statement {
    sid     = "AllowAssumeByEcsTasks"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "execution_role" {
  statement {
    sid    = "AllowECRLogging"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "task_role" {
  statement {
    sid    = "AllowDescribeCluster"
    effect = "Allow"

    actions = ["ecs:DescribeClusters"]

    resources = ["${aws_ecs_cluster.this.arn}"]
  }
}

data "aws_lb" "lb-ecs" {
  #arn  = "arn:aws:elasticloadbalancing:ap-northeast-2:160270626841:loadbalancer/app/dyheo-lb-ecs/ab3e32e5c83b808d"
  name = "${local.svc_nm}-lb-ecs"
}

resource "aws_iam_role" "execution_role" {
  name               = "${local.svc_nm}_ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_by_ecs.json}"
}

resource "aws_iam_role_policy" "execution_role" {
  role   = "${aws_iam_role.execution_role.name}"
  policy = "${data.aws_iam_policy_document.execution_role.json}"
}

resource "aws_iam_role" "task_role" {
  name               = "${local.svc_nm}_ecsTaskRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_by_ecs.json}"
}

resource "aws_iam_role_policy" "task_role" {
  role   = "${aws_iam_role.task_role.name}"
  policy = "${data.aws_iam_policy_document.task_role.json}"
}

resource "aws_security_group" "ecs" {
  name   = "${local.svc_nm}-sg-ecs"
  vpc_id = "${data.aws_vpc.this.id}"

## All VPC Port Open
#  ingress {
#    from_port       = 0
#    protocol        = "-1"
#    to_port         = 0
#    cidr_blocks = ["${data.aws_vpc.this.cidr_block}"]
#    security_groups = ["${data.aws_security_group.sg-core.id}"]
#  }

## Core Security Group 포함.
  ingress {
    from_port       = 0
    protocol        = "-1"
    to_port         = 0
    #cidr_blocks = ["${data.aws_vpc.this.cidr_block}"]
    security_groups = ["${data.aws_security_group.sg-core.id}"]
  }

## VPC 내에 모든 포트를 연다. ecs 에서 자동으로 다른 포트를 트라이 한다.
  ingress {
    from_port       = 0
    protocol        = "tcp"
    to_port         = 65535
    cidr_blocks = ["${data.aws_vpc.this.cidr_block}"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.svc_nm}-sg-ecs",
    Creator= "${local.creator}",
    Group = "${local.group}"
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.svc_nm}-ecs-cluster"
  tags = {
    Name = "${local.svc_nm}-ecs-cluster",
    Creator= "${local.creator}",
    Group = "${local.group}"
  }
}


