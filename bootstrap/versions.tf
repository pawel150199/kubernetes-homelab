terraform {
  required_version = ">= 1.15.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.69.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
  }
  backend "s3" {
    bucket       = "kubernetes-homelab-tfstate"
    key          = "terraform-bootstrap.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
}

provider "helm" {
  kubernetes = {
    config_path = "./kube-config/config"
  }
}

provider "kubernetes" {
  config_path = "./kube-config/config"
}
