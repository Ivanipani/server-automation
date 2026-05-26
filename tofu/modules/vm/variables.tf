# VMs to create on this module's (single) Proxmox node. The caller is
# tofu/modules/hypervisor (one per-node workspace per hypervisor),
# which slices the inventory-derived VM map down to guests pinned to
# its `var.hypervisor_name` and feeds the result here. Shape is produced
# by tofu/modules/hypervisor/locals.tf (`vms_for_this_node`) — keep the
# two in sync.
variable "vms" {
  description = "Map of VM name => shaped VM definition for this node"
  type = map(object({
    hostname    = string
    mac_address = string
    cores       = number
    memory      = number
    disk_size   = number
    ip_address  = string
    gateway     = string
    tags        = list(string)
    node        = string
    template_id = number
  }))
}
