# TODO: add ArgoCD installation
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
