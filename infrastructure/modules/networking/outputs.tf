output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnets.iddescription = "Contains a map of the ids of the public subnets"
  value = value = { for k, v in aws_subnet.public_subnets : k => v.id }
}

output "private_subnet_ids" {
  description = "Contains a map of the ids of the private subnets"
  value = { for k, v in aws_subnet.private_subnets : k => v.id }
}