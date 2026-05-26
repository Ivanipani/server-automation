# Single proxmox provider — this Tofu workspace serves ONE standalone
# PVE hypervisor only. Endpoint comes from inventory.yaml (single source
# of truth), token comes from Ansible at apply time
# (TF_VAR_proxmox_api_token, sourced from the per-node entry in
# `proxmox_api_tokens` in group_vars/all/vars.yml).

provider "proxmox" {
  endpoint  = local.endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent = true
  }
}
