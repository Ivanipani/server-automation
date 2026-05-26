# Proxmox API tokens, one per standalone hypervisor — passed in by
# Ansible (30-guests/10-opentofu.yml + 13-foundation/80-tofu-infra-lxcs.yml)
# as a single JSON-encoded `TF_VAR_proxmox_api_tokens` env var, sourced
# from the `proxmox_api_tokens` group var in group_vars/all/vars.yml.
#
# Keying contract: map keys MUST match the keys in inventory.yaml's
# all.vars.proxmox_endpoints — every aliased provider in
# tofu/provider.tf looks up its token here by hypervisor name.
#
# Adding a hypervisor: see the 3-step checklist in tofu/provider.tf.

variable "proxmox_api_tokens" {
  description = "Map of hypervisor name => Proxmox API token (user@realm!tokenid=secret). Keys MUST match all.vars.proxmox_endpoints in inventory.yaml."
  type        = map(string)
  sensitive   = true
}
