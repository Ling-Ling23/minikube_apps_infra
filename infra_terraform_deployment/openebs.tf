# OpenEBS Storage - Persistent Storage for Kubernetes
# Provides dynamic provisioning of persistent volumes

# OpenEBS namespace
resource "kubernetes_namespace" "openebs_system" {
  metadata {
    name = "openebs-system"
    
    labels = {
      name       = "openebs-system"
      created-by = "terraform"
      purpose    = "storage"
    }
  }
}

# Deploy OpenEBS using Helm
resource "helm_release" "openebs" {
  name       = "openebs"
  repository = "https://openebs.github.io/charts"
  chart      = "openebs"
  version    = "3.9.0"  # Latest stable version
  namespace  = kubernetes_namespace.openebs_system.metadata[0].name

  # OpenEBS configuration - optimized for minikube/development
  values = [
    yamlencode({
      # Enable local provisioner for minikube
      localprovisioner = {
        enabled = true
        # Configure hostpath provisioner
        hostpathClass = {
          enabled = true
          name = "openebs-hostpath"
          isDefaultClass = false
          basePath = "/var/openebs/local"
        }
      }

      # Enable LVM Local PV for more advanced storage
      lvm-localpv = {
        enabled = true
      }

      # Disable components not needed for minikube
      zfs-localpv = {
        enabled = false
      }
      
      mayastor = {
        enabled = false
      }

      # Disable NDM (Node Disk Manager) for minikube
      ndm = {
        enabled = false
      }
      
      ndmOperator = {
        enabled = false
      }

      # Admission server for validation
      webhook = {
        enabled = true
      }

      # OpenEBS control plane
      apiserver = {
        enabled = true
        # Resource limits for minikube
        resources = {
          limits = {
            cpu = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu = "50m"
            memory = "64Mi"
          }
        }
      }

      # Provisioner for local volumes
      provisioner = {
        enabled = true
        resources = {
          limits = {
            cpu = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu = "50m"
            memory = "64Mi"
          }
        }
      }

      # Snapshot controller
      snapshotOperator = {
        enabled = true
        controller = {
          resources = {
            limits = {
              cpu = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu = "50m"
              memory = "64Mi"
            }
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.openebs_system]
}

# Wait for OpenEBS components to be ready
resource "null_resource" "wait_for_openebs" {
  depends_on = [helm_release.openebs]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for OpenEBS pods to be ready..."
      kubectl wait --for=condition=Ready pod -l component=localpv-provisioner -n openebs-system --timeout=120s || true
      kubectl wait --for=condition=Ready pod -l app=openebs-lvm-controller -n openebs-system --timeout=120s || true
      kubectl wait --for=condition=Ready pod -l app=openebs-lvm-node -n openebs-system --timeout=120s || true
      echo "OpenEBS installation complete!"
      kubectl get storageclass
    EOT
  }
}