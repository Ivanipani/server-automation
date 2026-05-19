# VMs to create on this module's (single) Proxmox node. The caller
# (tofu/main.tf) partitions the inventory-derived VM map by node and
# passes only the subset whose `node` matches the provider this module
# instance is wired to. Shape is produced by tofu/locals.tf
# (vms_from_inventory) — keep the two in sync.
variable "vms" {
  description = "Map of VM name => shaped VM definition for this node"
  type = map(object({
    hostname       = string
    mac_address    = string
    cores          = number
    memory         = number
    disk_size      = number
    data_disk_size = number
    ip_address     = string
    gateway        = string
    tags           = list(string)
    node           = string
    template_id    = number
  }))
}
