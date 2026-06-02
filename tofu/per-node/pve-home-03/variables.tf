variable "proxmox_username" {
  description = "Proxmox API user (realm-qualified) that drives Tofu. The shared advanceteam@pve service account, created identically on every hypervisor by 20-hypervisor/15-tofu-service-account.yml and granted the scoped `Terraform` ACL role on /."
  type        = string
  default     = "advanceteam@pve"
}

variable "proxmox_password" {
  description = "Password for var.proxmox_username. A single well-known secret shared across every hypervisor. Supplied by Ansible at apply time via TF_VAR_proxmox_password, sourced from `advanceteam_user_pass` (re-export of vault_advanceteam_user_pass) in group_vars/all/vars.yml."
  type        = string
  sensitive   = true
}
