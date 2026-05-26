terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # No configuration_aliases — the caller (modules/hypervisor) has a
      # single default `proxmox` provider inherited from the per-node
      # directory (tofu/per-node/<host>/provider.tf), which serves one
      # standalone PVE host per Tofu workspace.
    }
  }
}
