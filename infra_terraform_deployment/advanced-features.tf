# Advanced Kubernetes features for production readiness

# Horizontal Pod Autoscaler for backend
resource "kubernetes_horizontal_pod_autoscaler_v2" "py3miniapp_backend_hpa" {
  metadata {
    name      = "py3miniapp-backend-hpa"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-backend"
      created-by = "terraform"
    }
  }

  spec {
    min_replicas = 1
    max_replicas = 3

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.py3miniapp_backend.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"  
          average_utilization = 50
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300  # Wait 5 minutes before scaling down
        select_policy = "Max"
        policy {
          type           = "Percent"
          value          = 50   # Scale down by max 50% of current replicas
          period_seconds = 60
        }
      }
      
      scale_up {
        stabilization_window_seconds = 60   # Wait 1 minute before scaling up  
        select_policy = "Max"
        policy {
          type           = "Percent"
          value          = 100  # Scale up by max 100% of current replicas (double)
          period_seconds = 30
        }
      }
    }
  }
}

# Pod Disruption Budget for backend
resource "kubernetes_pod_disruption_budget_v1" "py3miniapp_backend_pdb" {
  metadata {
    name      = "py3miniapp-backend-pdb"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-backend"
      created-by = "terraform"
    }
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "py3miniapp-backend"
      }
    }
  }
}

# Network Policy for backend - restrict ingress to only necessary traffic
resource "kubernetes_network_policy" "py3miniapp_backend_network_policy" {
  metadata {
    name      = "py3miniapp-backend-ingress-only"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-backend"
      created-by = "terraform"
    }
  }

  spec {
    # Apply this policy to backend pods
    pod_selector {
      match_labels = {
        app = "py3miniapp-backend"
      }
    }

    # Default deny all traffic
    policy_types = ["Ingress", "Egress"]

    # Allow ingress traffic
    ingress {
      # 1. Allow traffic from NGINX Ingress Controller
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name"      = "ingress-nginx"
            "app.kubernetes.io/component" = "controller"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    ingress {
      # 2. Allow health checks from Kubernetes (for liveness/readiness probes)
      # Allow from any namespace (kubelet health checks)
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # Allow egress traffic (backend needs to make outbound connections)
    egress {
      # 1. Allow DNS resolution to kube-system namespace
      to {
        namespace_selector {
          match_labels = {
            "name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP" 
        port     = "53"
      }
    }

    egress {
      # DNS TCP to kube-system
      to {
        namespace_selector {
          match_labels = {
            "name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    egress {
      # 2. Allow all external traffic for HTTPS, SSH, HTTP
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      # SSH for git
      ports {
        protocol = "TCP"  
        port     = "22"
      }
    }

    egress {
      # HTTP for package downloads
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }
  }
}