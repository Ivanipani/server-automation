variable "proxmox_api_token" {
  description = "Proxmox API token for this hypervisor (user@realm!tokenid=secret). Supplied by Ansible at apply time via TF_VAR_proxmox_api_token, sourced per-iteration from the `proxmox_api_tokens` map in group_vars/all/vars.yml."
  type        = string
  sensitive   = true
}
