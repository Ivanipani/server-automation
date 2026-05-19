# Per-node Proxmox API tokens. Independent nodes each have their own
# token (minted on that node: `pveum user token add root@pam tofu-lan
# --privsep 0`). They are passed in from Ansible via per-node
# TF_VAR_proxmox_api_token_<node> environment variables
# (05-provision-infrastructure.yml), sourced from the vault. Per-node
# string vars (not a single map) keep env passing unambiguous and match
# the unavoidable static per-node provider blocks in provider.tf.
#
# Adding a node: see the checklist in tofu/provider.tf.

variable "proxmox_api_token_pve_home_01" {
  description = "Proxmox API token for pve-home-01 (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_pve_home_02" {
  description = "Proxmox API token for pve-home-02 (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

# variable "containers" {
#   description = "Map of LXC containers to create"
#   type = map(object({
#     hostname     = string
#     cores        = optional(number, 1)
#     memory       = optional(number, 512)
#     swap         = optional(number, 512)
#     disk_size    = optional(number, 8)
#     ip_address   = optional(string, "dhcp")
#     gateway      = optional(string, "")
#     unprivileged = optional(bool, true)
#     tags         = optional(list(string), [])
#   }))
#   default = {}
# }
