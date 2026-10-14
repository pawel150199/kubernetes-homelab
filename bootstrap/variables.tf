variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID for the Tailscale Helm chart installation"
  type        = string
  default     = ""
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret"
  type        = string
  default     = ""
}