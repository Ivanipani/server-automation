proxmox_endpoint = "https://control01:8006"
proxmox_node     = "control01"

ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTl/C06oyAMQiGgvUyH4eT2C0sPsIEqnT2nDNHDQ5j9 ivanperdomo@Ivans-MacBook-Pro.local"

template_vm_id = 9001
template_ct_id = 9101

vms = {
  devbox01 = {
    hostname  = "devbox01"
    cores     = 4
    memory    = 4096
    disk_size = 40
    tags      = ["dev", "ivan"]
  }
}

containers = {
  caddy01 = {
    hostname  = "caddy01"
    cores     = 1
    memory    = 512
    disk_size = 4
    tags      = ["caddy", "webserver"]
  }
  nginx01 = {
    hostname  = "nginx01"
    cores     = 1
    memory    = 512
    disk_size = 8
    tags      = ["nginx", "webserver"]
  }
}
