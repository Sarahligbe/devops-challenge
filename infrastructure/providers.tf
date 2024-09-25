terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.67.0"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.32.0"
    }

    helm = {
      source = "hashicorp/helm"
      version = "2.15.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Configure the Kubernetes provider
provider "kubernetes" {
  host                   = yamldecode(local.kubeconfig).clusters[0].cluster.server
  cluster_ca_certificate = base64decode(yamldecode(local.kubeconfig).clusters[0].cluster.certificate-authority-data)
  client_certificate     = base64decode(yamldecode(local.kubeconfig).users[0].user.client-certificate-data)
  client_key             = base64decode(yamldecode(local.kubeconfig).users[0].user.client-key-data)
}

# Configure the Helm provider
provider "helm" {
  kubernetes {
    host                   = yamldecode(local.kubeconfig).clusters[0].cluster.server
    cluster_ca_certificate = base64decode(yamldecode(local.kubeconfig).clusters[0].cluster.certificate-authority-data)
    client_certificate     = base64decode(yamldecode(local.kubeconfig).users[0].user.client-certificate-data)
    client_key             = base64decode(yamldecode(local.kubeconfig).users[0].user.client-key-data)
  }
}