variable "cluster_name" {
  description = "K8s cluster name"
  type = string
}

variable "instance_type" {
  description = "Instance type for k8s nodes"
  type = string
  default = "t3.medium"
}

variable "private_subnet_ids" {
  description = "Contains a map of the ids of the private subnets"
  type = map(object)
}

variable "controlplane_sg_id" {
  description = "Security group ID of controlplane node"
  type = string
}

variable "worker_sg_id" {
  description = "Security group ID of worker node"
  type = string
}

variable "key_name" {
  description = "SSH key for access to the nodes"
  type = string
}