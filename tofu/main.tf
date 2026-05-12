resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms_from_inventory

  name        = each.value.hostname
  description = each.key
  # Every VM is cloned on the template node. Final placement is handled by
  # the HA resources below — Proxmox HA migrates the VM to its preferred
  # node after creation, and `lifecycle.ignore_changes = [node_name]` keeps
  # Tofu from fighting that migration on subsequent plans.
  node_name = local.template_vm_node
  tags      = each.value.tags

  clone {
    vm_id = each.value.template_id != null ? each.value.template_id : local.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    interface    = "virtio0"
    size         = each.value.disk_size
    datastore_id = "vms" # Ceph RBD; cluster-shared so VMs can live-migrate
  }

  # The cloud-init drive is attached because this block is present. VM `name`
  # propagates to cloud-init as the hostname (no explicit `hostname` field
  # exists on `initialization` in bpg/proxmox v0.106). The `ansible` user is
  # baked into the template by 04-prepare-templates.yml, so no `user_account`
  # block is needed. DNS server + search domain reach guests via DHCP options
  # set on the OPNsense dnsmasq side — keep DNS centrally managed there.
  initialization {
    datastore_id = "vms"

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.ip_address != "dhcp" ? each.value.gateway : null
      }
    }
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = each.value.mac_address
  }

  lifecycle {
    ignore_changes = [disk, node_name]
  }
}

# Per-VM HA enrollment. PVE 9.x replaced HA groups with HA rules, so the
# `group` field on this resource is no longer used — node placement is
# expressed exclusively via the `proxmox_harule` below, which requires
# the resources to be HA-managed first.
resource "proxmox_haresource" "vm" {
  for_each = local.vms_from_inventory

  resource_id = "vm:${proxmox_virtual_environment_vm.vm[each.key].vm_id}"
  state       = "started"
  comment     = "Managed by Tofu"
}

# One node-affinity rule per preferred node. `strict = false` allows
# fail-over to other cluster nodes if the preferred one is unavailable;
# the priority-2 entry pulls the VM back when the preferred node returns.
# The `resources` set references proxmox_haresource.vm so the rule waits
# for HA enrollment before being created.
resource "proxmox_harule" "pin" {
  for_each = toset([for h in local.vms_from_inventory : h.node])

  rule = "pin-${each.value}"
  type = "node-affinity"
  resources = toset([
    for name, h in local.vms_from_inventory :
    proxmox_haresource.vm[name].resource_id
    if h.node == each.value
  ])
  nodes = {
    (each.value) = 2
  }
  strict  = false
  comment = "Managed by Tofu - prefers ${each.value}"
}

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
#     vm_id = local.template_ct_id
#   }
#
#   features {
#     nesting = true
#   }
# }
