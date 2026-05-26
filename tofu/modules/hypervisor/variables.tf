variable "hypervisor_name" {
  description = "Inventory key for this hypervisor (e.g. 'pve-home-01'). Used to slice the inventory walk down to guests pinned to this node, and to look up template anchors."
  type        = string
}
