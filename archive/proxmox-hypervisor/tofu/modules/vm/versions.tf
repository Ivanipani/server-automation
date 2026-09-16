terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # No configuration_aliases — the caller (modules/hypervisor) has a
      # single default `proxmox` provider inherited from the flat root
      # (tofu/node/provider.tf), which serves one standalone PVE host per
      # named tofu workspace.
    }
  }
}
