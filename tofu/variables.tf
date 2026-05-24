# Per-hypervisor Proxmox API tokens. Independent nodes each have their
# own token (minted on that node: `pveum user token add root@pam
# tofu-lan --privsep 0`). They are passed in from Ansible via per-node
# TF_VAR_proxmox_api_token_<node> environment variables
# (30-guests/10-opentofu.yml), sourced from the vault. Per-node string
# vars (not a single map) keep env passing unambiguous and match the
# unavoidable static per-node provider blocks in provider.tf.
#
# Adding a hypervisor: see the checklist in tofu/provider.tf.

variable "proxmox_api_token_pve_home_01" {
  description = "Proxmox API token for pve-home-01 (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

# NOTE: an `ansible_pubkey` variable used to live here for injecting the
# canonical key into LXCs at create time via
# `initialization.user_account.keys`. That hit a PVE container-clone API
# constraint (ssh-public-keys not in the clone schema), so the LXC
# module no longer uses it — the Debian LXC template (baked by
# tasks/create-lxc-template.yml) already installs the key on the
# ansible user, so the cloned LXC is reachable immediately. If a future
# resource genuinely needs a controller-supplied secret, re-introduce a
# variable here.

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
