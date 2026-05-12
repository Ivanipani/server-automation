provider "proxmox" {
  endpoint  = local.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent = true
  }
}
