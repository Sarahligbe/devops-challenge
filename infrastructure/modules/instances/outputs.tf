output "controlplane_instance_id" {
  description = "K8s control plane instance ID"
  value = aws_instance.controlplane.id
}

output "worker_instance_id" {
  description = "K8s worker instance ID"
  value = aws_instance.worker.id
}