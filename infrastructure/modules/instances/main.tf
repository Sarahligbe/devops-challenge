data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_key_pair" "main" {
  key_name           = "var.key_name"
}

resource "aws_instance" "controlplane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids
  vpc_security_group_ids = var.controlplane_sg_id
  key_name               = data.aws_key_pair.main.key_name

  user_data = templatefile("userdata.sh", {node = "controlplane"})

  tags = {
    Name = "k8s_controlplane"
  }
}

resource "aws_instance" "worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids
  vpc_security_group_ids = var.worker_sg_id
  key_name               = data.aws_key_pair.main.key_name

  user_data = templatefile("userdata.sh", {node = "worker"})

  tags = {
    Name = "k8s_worker"
  }
}