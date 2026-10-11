variable "tailscale_auth_key" {
  description = "Tailscale auth key for node authentication"
  type        = string
  sensitive   = true
  default     = null
}
