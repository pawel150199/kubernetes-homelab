# Tailscale bootstrap configuration
resource "kubernetes_namespace_v1" "tailscale" {
  metadata {
    name = "tailscale"
    labels = {
      application = "tailscale"
    }
  }
}

resource "helm_release" "tailscale" {
  name       = "tailscale"
  repository = "https://pkgs.tailscale.com/helmcharts/"
  chart      = "tailscale-operator"
  namespace  = kubernetes_namespace_v1.tailscale.metadata[0].name
  version    = "0.1.0"
  values = [
    file("${path.module}/values/tailscale.yaml")
  ]
}

# Argocd bootstrap configuration
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      application = "argocd"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  version    = "10.10.2"
  values = [
    file("${path.module}/values/argocd.yaml")
  ]

  depends_on = [
    kubernetes_namespace_v1.argocd
  ]
}
