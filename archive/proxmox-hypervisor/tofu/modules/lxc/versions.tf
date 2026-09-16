terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # No configuration_aliases — same shape as modules/vm: the caller
      # (modules/hypervisor) has a single default `proxmox` provider,
      # which serves one standalone PVE host per Tofu workspace.
    }
  }
}
