variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "private_subnet_blocks" {
  description = "CIDR blocks and availability zones for private subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "public_subnet_blocks" {
  description = "CIDR blocks and availability zones for public subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "instance_type" {
  description = "EC2 instance type for Kubernetes nodes"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
}