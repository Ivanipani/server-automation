# One `vm` module instance per Proxmox node, each wired to that node's
# aliased provider (provider.tf) and fed only the VMs pinned to it
# (locals.vms_by_node). Independent nodes don't share an API, so a VM on
# pve-home-02 must be created through pve-home-02's own provider — the
# module-per-node split is what makes that possible (Terraform won't let
# `providers` be selected dynamically inside a single resource).
#
# Adding a node: see the checklist in tofu/provider.tf.

module "vms_pve_home_01" {
  source    = "./modules/vm"
  vms       = local.vms_by_node["pve-home-01"]
  providers = { proxmox = proxmox.pve_home_01 }
}

module "vms_pve_home_02" {
  source    = "./modules/vm"
  vms       = local.vms_by_node["pve-home-02"]
  providers = { proxmox = proxmox.pve_home_02 }
}

# LXC containers (dormant reference — not currently provisioned). When
# revived, the same module-per-node pattern applies: a container module
# instantiated per node with that node's aliased provider.
#
# resource "proxmox_virtual_environment_container" "ct" {
#   for_each = var.containers
#
#   node_name    = var.proxmox_node
#   tags         = each.value.tags
#   unprivileged = each.value.unprivileged
#
#   initialization {
#     hostname = each.value.hostname
#
#     ip_config {
#       ipv4 {
#         address = each.value.ip_address
#         gateway = each.value.ip_address != "dhcp" ? each.value.gateway : null
#       }
#     }
#
#   }
#
#   console {
#     enabled   = true
#     tty_count = 2
#     type      = "tty"
#   }
#
#   cpu {
#     cores = each.value.cores
#   }
#
#   memory {
#     dedicated = each.value.memory
#     swap      = each.value.swap
#   }
#
#   disk {
#     datastore_id = "local-zfs"
#     size         = each.value.disk_size
#   }
#
#   network_interface {
#     name   = "eth0"
#     bridge = "vmbr0"
#   }
#
#   clone {
#     vm_id = local.inventory.all.vars.template_ct_ids[var.proxmox_node]
#   }
#
#   features {
#     nesting = true
#   }
# }
