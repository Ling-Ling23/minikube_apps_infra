
# Ingress 
resource "kubernetes_ingress_v1" "my_app_ingress" {
  metadata {
    name      = "my-app-ingress"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    
    labels = {
      app        = "py3miniapp"
      created-by = "terraform"
    }
    
    annotations = {
      "nginx.ingress.kubernetes.io/use-regex"           = "true"
      "nginx.ingress.kubernetes.io/rewrite-target"      = "/$2"
      "cert-manager.io/issuer"                          = "local-root-ca-issuer"
      "nginx.ingress.kubernetes.io/ssl-redirect"        = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect"  = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"
    
    tls {
      hosts       = ["myapp.local"]
      secret_name = "myapp-local-tls"
    }

    rule {
      host = "myapp.local"
      http {
        path {
          path      = "/app1_backend(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = kubernetes_service.py3miniapp_backend_service.metadata[0].name
              port {
                number = 5000
              }
            }
          }
        }
        path {
          path      = "/app1_frontend(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "py3miniapp-frontend-service"  # This service doesn't exist yet
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}