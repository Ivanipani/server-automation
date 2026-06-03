variable "proxmox_endpoint" {
  description = "OPTIONAL override for the Proxmox API URL, e.g. https://pve-home-01.lan:8006 (or an IP / alt port). Normally left empty: the endpoint is derived by convention from hypervisor_name + all.vars.domain (https://<hypervisor_name>.<domain>:8006). Set it only for manual CLI use when the convention doesn't apply."
  type        = string
  default     = ""
}

variable "hypervisor_name" {
  description = "Inventory key of the node to provision (e.g. 'pve-home-01'). Slices the inventory walk + template-id lookups in modules/hypervisor. Defaults to the tofu workspace name when empty, so `tofu workspace select <node>` is sufficient for manual runs; Ansible passes it explicitly."
  type        = string
  default     = ""
}

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
