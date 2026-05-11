resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name        = each.value.hostname
  description = each.key
  node_name   = each.value.node != null ? each.value.node : var.proxmox_node
  tags        = each.value.tags

  clone {
    vm_id = each.value.template_id != null ? each.value.template_id : var.template_vm_id
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
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [disk]
  }
}

resource "proxmox_virtual_environment_container" "ct" {
  for_each = var.containers

  node_name    = var.proxmox_node
  tags         = each.value.tags
  unprivileged = each.value.unprivileged

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.ip_address != "dhcp" ? each.value.gateway : null
      }
    }

  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = "local-zfs"
    size         = each.value.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  clone {
    vm_id = var.template_ct_id
  }

  features {
    nesting = true
  }
}
