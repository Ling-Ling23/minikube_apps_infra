# APP 1 - Service Account for backend pods
resource "kubernetes_service_account" "py3miniapp_backend_sa" {
  metadata {
    name      = "py3miniapp-backend-sa"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-backend"
      created-by = "terraform"
    }
  }
  
  # Disable automatic mounting of service account token for security
  automount_service_account_token = false
}

# APP 1 - Service Account for frontend pods
resource "kubernetes_service_account" "py3miniapp_frontend_sa" {
  metadata {
    name      = "py3miniapp-frontend-sa"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-frontend"
      created-by = "terraform"
    }
  }
  
  # Disable automatic mounting of service account token for security
  automount_service_account_token = false
}

# APP 1 - Python 3 Mini App Backend Deployment
resource "kubernetes_deployment" "py3miniapp_backend" {
  metadata {
    name      = "py3miniapp-backend"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-backend"
      created-by = "terraform"
    }
  }

  spec {
    replicas = var.app_replicas_backend

    selector {
      match_labels = {
        app = "py3miniapp-backend"
      }
    }

    template {
      metadata {
        labels = {
          app = "py3miniapp-backend"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "80"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        # Use our custom service account for security
        service_account_name = kubernetes_service_account.py3miniapp_backend_sa.metadata[0].name
        
        # Pod-level security context (matches working YAML)
        security_context {
          fs_group = 65534  # nobody group
          # runAsNonRoot, runAsUser, runAsGroup commented out for development
        }

        container {
          name  = "py3miniapp-backend"
          image = "ghcr.io/ling-ling23/py3miniapp:v1"

          port {
            container_port = 80
          }

          # Environment variables - now using dynamic git branch!
          env {
            name  = "PROJECT_DIR"
            value = var.project_dir
          }

          env {
            name  = "PROJECT_GIT_BRANCH"
            value = local.current_git_branch
          }

          env {
            name  = "PROJECT_GIT_URL"
            value = var.project_git_url
          }

          # Liveness probe to check if container is healthy
          liveness_probe {
            http_get {
              path = "/live"
              port = 80
            }
            initial_delay_seconds = 15
            failure_threshold     = 10
            timeout_seconds       = 2
            period_seconds        = 20
          }

          # Container-level security context (temporarily disabled for debugging)
          # security_context {
          #   read_only_root_filesystem  = false  # Allow writing for development
          #   allow_privilege_escalation = false
          #   capabilities {
          #     drop = ["ALL"]  # Match working YAML exactly
          #   }
          #   seccomp_profile {
          #     type = "RuntimeDefault"
          #   }
          # }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# APP 1 - Service to expose the backend deployment
resource "kubernetes_service" "py3miniapp_backend_service" {
  metadata {
    name      = "py3miniapp-backend-service"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-backend"
      created-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "py3miniapp-backend"
    }

    port {
      protocol    = "TCP"
      port        = 5000
      target_port = 80
    }

    type = "ClusterIP"
  }
}


# APP 1 - Python 3 Mini App frontend Deployment
resource "kubernetes_deployment" "py3miniapp_frontend" {
  metadata {
    name      = "py3miniapp-frontend"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-frontend"
      created-by = "terraform"
    }
  }

  spec {
    replicas = var.app_replicas_frontend

    selector {
      match_labels = {
        app = "py3miniapp-frontend"
      }
    }

    template {
      metadata {
        labels = {
          app = "py3miniapp-frontend"
        }
        annotations = {
          "prometheus.io/scrape" = "true" 
          "prometheus.io/port"   = "80"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        # Use our custom service account for security
        service_account_name = kubernetes_service_account.py3miniapp_frontend_sa.metadata[0].name
        
        # Pod-level security context (matches working YAML)
        security_context {
          fs_group = 65534  # nobody group
          # runAsNonRoot, runAsUser, runAsGroup commented out for development
        }

        container {
          name  = "py3miniapp-frontend"
          image = "ghcr.io/ling-ling23/py3miniapp:v1"

          port {
            container_port = 80
          }

          # Environment variables - now using dynamic git branch!
          env {
            name  = "PROJECT_DIR"
            value = var.project_dir
          }

          env {
            name  = "PROJECT_GIT_BRANCH"
            value = local.current_git_branch
          }

          env {
            name  = "PROJECT_GIT_URL"
            value = var.project_git_url
          }

          # Liveness probe to check if container is healthy
          liveness_probe {
            http_get {
              path = "/live"
              port = 80
            }
            initial_delay_seconds = 15
            failure_threshold     = 10
            timeout_seconds       = 2
            period_seconds        = 20
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# APP 1 - Service to expose the backend deployment
resource "kubernetes_service" "py3miniapp_frontend_service" {
  metadata {
    name      = "py3miniapp-frontend-service"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp-frontend"
      created-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "py3miniapp-frontend"
    }

    port {
      protocol    = "TCP"
      port        = 5000
      target_port = 80
    }

    type = "ClusterIP"
  }
}
