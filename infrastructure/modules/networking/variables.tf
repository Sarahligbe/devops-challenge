variable "cluster_name" {
  description = "K8s cluster name"
  type = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block"
  type = string
}

variable "private_subnet_blocks" {
  description = "cidr, availability zone for private subnets"
  type = map(object({
    cidr = string
    az = string
  }))
}

variable "public_subnet_blocks" {
  description = "cidr, availability zone for public subnets"
  type = map(object({
    cidr = string
    az = string
  }))
}

variable "eice_sg_id" {
  description = "EC2 instance connect security group ID"
  type = string
}