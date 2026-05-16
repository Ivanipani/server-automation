resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms_from_inventory

  name        = each.value.hostname
  description = each.key
  # Storage is node-local LVM-thin, so each VM is created directly on its
  # preferred node and cloned from that node's own per-node template.
  # There is no HA / live-migration — a VM lives and stays on one node.
  node_name = each.value.node
  tags      = each.value.tags

  clone {
    vm_id = each.value.template_id
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
    datastore_id = "vms" # node-local LVM-thin; VM is pinned to its node
  }

  # Optional second disk for k3s workers (Longhorn data), backed by the
  # node-local `longhorn-data` LVM-thin pool. Emitted only when the host
  # declares `vm.data_disk_size` in inventory.yaml. Presents as virtio1
  # (/dev/vdb) in the guest; 09b-longhorn-storage.yml formats+mounts it.
  dynamic "disk" {
    for_each = each.value.data_disk_size > 0 ? [1] : []
    content {
      interface    = "virtio1"
      size         = each.value.data_disk_size
      datastore_id = "longhorn-data"
    }
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
    # `disk` churns from cloud-init / qemu runtime attributes — ignore it
    # (covers the optional second data disk too). `node_name` is now
    # authoritative from Tofu; there is no HA to fight over placement.
    ignore_changes = [disk]
  }
}

# No proxmox_haresource / proxmox_harule: storage is node-local LVM-thin,
# so HA failover to a node lacking the VM's disk is invalid. Placement is
# expressed solely by `node_name` above (the VM's inventory proxmox_node).

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
