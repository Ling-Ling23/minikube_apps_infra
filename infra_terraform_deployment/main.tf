terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

# This configures the Kubernetes provider to connect to our Minikube cluster
provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "terraform-learning" {
  metadata {
    name = "terraform-learning"
    
    labels = {
      created-by = "terraform"
      purpose    = "apps"
    }
  }
}