module "networking" {
  source = "./networking"

  cluster_name           = var.cluster_name
  vpc_cidr_block         = var.vpc_cidr_block
  private_subnet_blocks  = var.private_subnet_blocks
  public_subnet_blocks   = var.public_subnet_blocks
  eice_sg_id             = module.security_groups.eice_sg_id
}

module "security_groups" {
  source = "./security_groups"

  cluster_name    = var.cluster_name
  vpc_id          = module.networking.vpc_id
  vpc_cidr_block  = var.vpc_cidr_block
}

module "iam" {
  source = "./iam"

  k8s_join_command_arn = module.instances.k8s_join_command_arn
}

module "instances" {
  source = "./instances"

  cluster_name       = var.cluster_name
  instance_type      = var.instance_type
  private_subnet_ids = module.networking.private_subnet_ids
  controlplane_sg_id = module.security_groups.controlplane_sg_id
  worker_sg_id       = module.security_groups.worker_sg_id
  key_name           = var.key_name #provide the key name of an existing ssh key you own
  ssm_profile_name   = module.iam.ssm_profile_name
}