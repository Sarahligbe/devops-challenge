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

locals {
  node_configs = {
    controlplane = {
      count        = 1
      name         = "k8s_controlplane"
      subnet_index = 0
      sg_id        = var.controlplane_sg_id
      node_type    = "controlplane"
    },
    worker = {
      count        = 1  # or more if you want multiple workers
      name         = "k8s_worker"
      subnet_index = 1
      sg_id        = var.worker_sg_id
      node_type    = "worker"
    }
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

resource "aws_instance" "k8s_nodes" {
  for_each = local.node_configs

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[each.value.subnet_index]
  vpc_security_group_ids = [each.value.sg_id]
  key_name               = data.aws_key_pair.main.key_name
  iam_instance_profile   = var.ssm_profile_name

  user_data = templatefile("${path.module}/userdata.sh", { 
    node_type = each.value.node_type 
  })

  tags = {
    Name = each.value.name
  }

  count = each.value.count

  depends_on = [aws_ssm_parameter.k8s_join_command]
}