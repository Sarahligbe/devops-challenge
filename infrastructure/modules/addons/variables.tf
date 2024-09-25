variable "domain" {
  description = "Domain name"
  type = string
}

variable "argopass" {
  description = "ArgoCD password"
  type = string
}

variable "grafana_passwd" {
  description = "Grafana password"
  type = string
}

variable "enable_argocd" {
  description = "Enable ArgoCD installation"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring setup"
  type        = bool
  default     = true
}
