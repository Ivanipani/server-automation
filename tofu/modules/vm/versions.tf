terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # The caller passes a node-specific aliased provider via the
      # `providers = { proxmox = proxmox.<node> }` meta-argument. This
      # module is instantiated once per Proxmox node so it can target an
      # independent (non-clustered) node's own API endpoint.
      configuration_aliases = [proxmox]
    }
  }
}
