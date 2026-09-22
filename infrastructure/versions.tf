terraform {
  required_version = ">= 1.15.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.69.0"
    }
  }
  backend "s3" {
    bucket       = "kubernetes-homelab-tfstate"
    key          = "terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
}
