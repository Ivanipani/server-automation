terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Per-node aliased provider is passed in by the caller via
      # `providers = { proxmox = proxmox.<node> }`, same shape as
      # tofu/modules/vm — independent (non-clustered) nodes are
      # addressed through their own API endpoint.
      configuration_aliases = [proxmox]
    }
  }
}
