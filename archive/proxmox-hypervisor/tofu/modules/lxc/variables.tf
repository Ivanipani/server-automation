# LXCs to create on this module's (single) Proxmox node. Shape mirrors
# tofu/modules/vm/variables.tf — the caller is tofu/modules/hypervisor,
# which slices the inventory-derived LXC map down to guests pinned to
# its `var.hypervisor_name` AND tagged `infra`, and feeds the result
# here. Shape is produced by tofu/modules/hypervisor/locals.tf
# (`infra_lxcs_for_this_node`) — keep the two in sync.
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
