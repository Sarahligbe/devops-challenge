cluster_name = "lifi_project"
vpc_cidr_block = "172.19.0.0/16"
private_subnet_blocks = {
  priv_subnet_01 = {
    cidr = "172.19.0.0/19"
    az = "eu-west-1a"
  }
  priv_subnet_02 = {
    cidr = "172.19.32.0/19"
    az = "eu-west-1b"
  }
}
public_subnet_blocks = {
  pub_subnet_01 = {
    cidr = "172.19.64.0/19"
    az = "eu-west-1a"
  }
  pub_subnet_02 = {
    cidr = "172.19.96.0/19"
    az = "eu-west-1b"
  }
}
key_name = "lifi"