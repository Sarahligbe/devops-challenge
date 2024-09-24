output "controlplane_role_name" {
  description = "controlplane role name"
  value = aws_iam_role.k8s_controlplane_role.name
}

output "controlplane_profile_name" {
  description = "controlplane role name"
  value = aws_iam_instance_profile.controlplane_profile.name
}

output "worker_role_name" {
  description = "worker role name"
  value = aws_iam_role.k8s_worker_role.name
}

output "worker_profile_name" {
  description = "worker role name"
  value = aws_iam_instance_profile.worker_profile.name
}