# Certificate management for the terraform-learning namespace

# 1. Bootstrap a temporary self-signed root issuer (ClusterIssuer - available across all namespaces)
resource "kubectl_manifest" "selfsigned_bootstrap" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "selfsigned-bootstrap"
    }
    spec = {
      selfSigned = {}
    }
  })
}

# 2. Use bootstrap issuer to mint a root CA certificate (stored as a secret)
resource "kubectl_manifest" "local_root_ca" {
  depends_on = [kubectl_manifest.selfsigned_bootstrap]
  
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "local-root-ca"
      namespace = "default"
    }
    spec = {
      isCA       = true
      commonName = "local.dev.root.ca"
      secretName = "local-root-ca-secret"
      privateKey = {
        algorithm = "RSA"
        size      = 2048
      }
      issuerRef = {
        name = "selfsigned-bootstrap"
        kind = "ClusterIssuer"
      }
    }
  })
}

# 3. Read the root CA secret from default namespace
data "kubernetes_secret" "root_ca_from_default" {
  depends_on = [kubectl_manifest.local_root_ca]
  
  metadata {
    name      = "local-root-ca-secret"
    namespace = "default"
  }
}

# 4. Copy the root CA secret to our terraform-learning namespace
resource "kubernetes_secret" "local_root_ca_secret" {
  depends_on = [data.kubernetes_secret.root_ca_from_default]
  
  metadata {
    name      = "local-root-ca-secret"
    namespace = kubernetes_namespace.terraform-learning.metadata[0].name
  }
  
  data = data.kubernetes_secret.root_ca_from_default.data
  type = "kubernetes.io/tls"
}

# 5. Define a namespaced Issuer backed by the generated CA secret
resource "kubectl_manifest" "local_root_ca_issuer" {
  depends_on = [kubernetes_secret.local_root_ca_secret]
  
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "local-root-ca-issuer"
      namespace = kubernetes_namespace.terraform-learning.metadata[0].name
    }
    spec = {
      ca = {
        secretName = "local-root-ca-secret"
      }
    }
  })
}

# Note: The certificate for myapp.local is automatically created by the ingress
# annotation "cert-manager.io/issuer" = "local-root-ca-issuer" in ingress.tf
# No explicit Certificate resource needed - cert-manager handles it automatically!