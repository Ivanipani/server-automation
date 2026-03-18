resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name        = each.value.hostname
  description = each.key
  node_name   = var.proxmox_node
  tags        = each.value.tags

  clone {
    vm_id = var.template_vm_id
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
    datastore_id = "local-lvm"
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.ip_address != "dhcp" ? each.value.gateway : null
      }
    }

    user_account {
      username = "temp"
      keys     = [var.ssh_public_key]
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

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  console {
    enabled  = true
    tty_count = 2
    type     = "tty"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = "local-lvm"
    size         = each.value.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      operating_system[0].template_file_id,
    ]
  }
}
