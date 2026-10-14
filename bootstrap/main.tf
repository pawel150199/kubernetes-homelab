# Tailscale bootstrap configuration
resource "kubernetes_namespace_v1" "tailscale" {
  metadata {
    name = "tailscale"
    labels = {
      application = "tailscale"
    }
  }
}

# Two variables are required to be set in the terraform.tfvars file or using environment variables:
# TF_VAR_tailscale_oauth_client_id and TF_VAR_tailscale_oauth_client_secret

# Check if the required variables are set

# tailscale oauth client ID
check "tailscale_oauth_client_id" {
  assert {
    condition     = var.tailscale_oauth_client_id != ""
    error_message = "tailscale_oauth_client_id is required. Please set it in terraform.tfvars or as an environment variable."
  }
}

# tailscale oauth client secret
check "tailscale_oauth_client_secret" {
  assert {
    condition     = var.tailscale_oauth_client_secret != ""
    error_message = "tailscale_oauth_client_secret is required. Please set it in terraform.tfvars or as an environment variable."
  }
}

# Tailscale helm chart installation
resource "helm_release" "tailscale" {
  name       = "tailscale"
  repository = "https://pkgs.tailscale.com/helmcharts/"
  chart      = "tailscale-operator"
  namespace  = kubernetes_namespace_v1.tailscale.metadata[0].name
  version    = "1.104.1"
  set = [
    {
      name  = "oauth.clientId"
      value = var.tailscale_oauth_client_id
    },
    {
      name  = "oauth.clientSecret"
      value = var.tailscale_oauth_client_secret
    }
  ]
  depends_on = [
    kubernetes_namespace_v1.tailscale
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
