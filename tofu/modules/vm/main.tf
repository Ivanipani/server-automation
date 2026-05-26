# VMs for ONE standalone Proxmox hypervisor. Instantiated by
# tofu/modules/hypervisor, which inherits the per-node directory's
# single proxmox provider and feeds the inventory slice pinned to that
# hypervisor.
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

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
    ignore_changes = [disk]
  }
}
