# LXCs to create on this module's (single) Proxmox node. Shape mirrors
# tofu/modules/vm/variables.tf — the caller (tofu/main.tf) partitions
# the inventory-derived LXC map by node and feeds this module only the
# slice whose `node` matches the provider this instance is wired to.
# Shape is produced by tofu/locals.tf (lxcs_from_inventory) — keep the
# two in sync.
variable "lxcs" {
  description = "Map of LXC name => shaped LXC definition for this node"
  type = map(object({
    hostname     = string
    cores        = number
    memory       = number
    swap         = number
    disk_size    = number
    unprivileged = bool
    nesting      = bool
    tags         = list(string)
    node         = string
    template_id  = number
  }))
}
