variable "cluster_name" {
  description = "K8s cluster name"
  type = string
}

variable "region" {
  description = "AWS region"
  type = string
}

variable "instance_type" {
  description = "Instance type for k8s nodes"
  type = string
  default = "t3.medium"
}

variable "private_subnet_ids" {
  description = "Contains a list of the ids of the private subnets"
  type = list
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

variable "controlplane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1
}

variable "controlplane_profile_name" {
  description = "controlplane iam instance profile name"
  type        = string
}

variable "worker_profile_name" {
  description = "worker iam instance profile name"
  type        = string
}

variable "discovery_bucket_name" {
  description = "Name of s3 bucket were the IRSA keys are stored"
  type        = string
}