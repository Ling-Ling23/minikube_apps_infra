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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# This configures the Kubernetes provider to connect to our Minikube cluster
# Configure the Kubernetes Provider
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Configure the kubectl Provider  
provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Configure the Helm Provider
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
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