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
  filter {
    name   = "key-name"
    values = [var.key_name]
  }
}

resource "aws_ssm_parameter" "k8s_join_command" {
  name        = "/k8s/join-command"
  description = "Kubernetes cluster join command"
  type        = "SecureString"
  value       = "placeholder"  # This will be updated dynamically using the userdata script

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_instance" "controlplane" {
  count                  = var.controlplane_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.controlplane_sg_id]
  key_name               = data.aws_key_pair.main.key_name
  source_dest_check      = false
  iam_instance_profile   = var.ssm_profile_name

  user_data = templatefile("${path.module}/userdata.sh", {node_type = "controlplane", region = "${var.region}", discovery_bucket_name = "${var.discovery_bucket_name}"})

  tags = {
    Name = "k8s-controlplane-${count.index + 1}"
  }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[(count.index + 1) % length(var.private_subnet_ids)] 
  vpc_security_group_ids = [var.worker_sg_id]
  key_name               = data.aws_key_pair.main.key_name
  source_dest_check      = false
  iam_instance_profile   = var.ssm_profile_name

  user_data = templatefile("${path.module}/userdata.sh", {node_type = "worker", region = "${var.region}", discovery_bucket_name = "${var.discovery_bucket_name}"})

  tags = {
    Name = "k8s-worker-${count.index + 1}"
  }

  depends_on = [aws_instance.controlplane]
}