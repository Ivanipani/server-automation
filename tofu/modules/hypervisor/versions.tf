terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # No configuration_aliases — the caller (the flat tofu/node/ root)
      # has a single default `proxmox` provider; the child vm + lxc
      # modules inherit it through the module chain.
    }
  }
}
