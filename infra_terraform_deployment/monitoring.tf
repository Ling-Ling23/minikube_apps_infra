# Monitoring Stack - Prometheus & Grafana using Helm
# Using kube-prometheus-stack Helm chart - industry standard approach

# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    
    labels = {
      name       = "monitoring"
      created-by = "terraform"
      purpose    = "observability"
    }
  }
}

# Deploy kube-prometheus-stack with simplified configuration
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "51.2.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Simplified values configuration
  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          externalUrl = "https://myapp.local/prometheus"
          routePrefix="/"
          #
          retention = "30d"
          # Enable ServiceMonitor discovery across all namespaces
          serviceMonitorSelectorNilUsesHelmValues = false
          serviceMonitorSelector = {}
          serviceMonitorNamespaceSelector = {}
          # Storage configuration with OpenEBS
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "openebs-hostpath"
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
        # Disable built-in ingress - we'll create separate ones
        ingress = {
          enabled = false
        }
      }

      # Grafana configuration
      grafana = {
        adminPassword = "admin123"
        
        # Configure Grafana to serve from /grafana path
        "grafana.ini" = {
          server = {
            root_url = "https://myapp.local/grafana"
            serve_from_sub_path = true
            domain = "myapp.local"
            enforce_domain = false
            disable_login_form = false
            disable_signout_menu = false
          }
        }
        
        # Persistence with OpenEBS
        persistence = {
          enabled = true
          storageClassName = "openebs-hostpath"
          size = "1Gi"
          accessModes = ["ReadWriteOnce"]
        }
        
        # Disable built-in ingress - we'll create separate ones
        ingress = {
          enabled = false
        }
      }

      # AlertManager configuration
      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "openebs-hostpath"
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "2Gi"
                  }
                }
              }
            }
          }
        }
      }

      # Enable components
      nodeExporter = {
        enabled = true
      }
      
      kubeStateMetrics = {
        enabled = true
      }

      # Default monitoring rules
      defaultRules = {
        create = true
        rules = {
          alertmanager = true
          etcd = true
          general = true
          k8s = true
          kubeApiserver = true
          kubelet = true
          kubernetesApps = true
          kubernetesResources = true
          kubernetesStorage = true
          kubernetesSystem = true
          node = true
          prometheus = true
          prometheusOperator = true
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.openebs
  ]
}

# ServiceMonitor for your py3miniapp backend service
resource "kubectl_manifest" "py3miniapp_service_monitor" {
  depends_on = [helm_release.kube_prometheus_stack]
  
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind = "ServiceMonitor"
    metadata = {
      name = "py3miniapp-backend-monitor"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        app = "py3miniapp"
        created-by = "terraform"
        # This label is important for Prometheus to discover this ServiceMonitor
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "py3miniapp-backend"
        }
      }
      namespaceSelector = {
        matchNames = ["terraform-learning"]
      }
      endpoints = [
        {
          port = "http"
          path = "/metrics"
          interval = "30s"
        }
      ]
    }
  })
}

# ServiceMonitor for your py3miniapp frontend service
resource "kubectl_manifest" "py3miniapp_frontend_service_monitor" {
  depends_on = [helm_release.kube_prometheus_stack]
  
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind = "ServiceMonitor"
    metadata = {
      name = "py3miniapp-frontend-monitor"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        app = "py3miniapp"
        created-by = "terraform"
        # This label is important for Prometheus to discover this ServiceMonitor
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "py3miniapp-frontend"
        }
      }
      namespaceSelector = {
        matchNames = ["terraform-learning"]
      }
      endpoints = [
        {
          port = "http"
          path = "/metrics"
          interval = "30s"
        }
      ]
    }
  })
}

# Separate Ingress resources (similar to your working monitoring-ingress.yaml)
resource "kubernetes_ingress_v1" "grafana_ingress" {
  depends_on = [helm_release.kube_prometheus_stack]
  
  metadata {
    name      = "grafana-ingress"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "cert-manager.io/issuer" = "local-root-ca-issuer"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"
    
    tls {
      hosts       = ["myapp.local"]
      secret_name = "myapp-local-tls-monitoring"
    }

    rule {
      host = "myapp.local"
      http {
        path {
          path      = "/grafana"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "prometheus_ingress" {
  depends_on = [helm_release.kube_prometheus_stack]
  
  metadata {
    name      = "prometheus-ingress"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "cert-manager.io/issuer" = "local-root-ca-issuer"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
    }
  }

  spec {
    ingress_class_name = "nginx"
    
    tls {
      hosts       = ["myapp.local"]
      secret_name = "myapp-local-tls-prometheus"
    }

    rule {
      host = "myapp.local"
      http {
        path {
          path      = "/prometheus(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "kube-prometheus-stack-prometheus"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }
}