# Single proxmox provider — this Tofu workspace serves ONE standalone
# PVE hypervisor only. Endpoint comes from inventory.yaml (single source
# of truth); auth is the shared advanceteam@pve service account, supplied
# by Ansible at apply time (TF_VAR_proxmox_password, sourced from the
# well-known `advanceteam_user_pass` secret in group_vars/all/vars.yml).
# The same username + password authenticate to EVERY hypervisor — the
# account is created identically on each node by
# 20-hypervisor/15-tofu-service-account.yml.

provider "proxmox" {
  endpoint = local.endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true

  ssh {
    agent = true
  }
}
