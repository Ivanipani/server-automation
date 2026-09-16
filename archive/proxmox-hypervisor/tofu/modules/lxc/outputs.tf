output "lxc_ips" {
  description = "LXC name => discovered IPv4 addresses for this node"
  value = {
    for name, ct in proxmox_virtual_environment_container.ct :
    name => try(ct.ipv4_addresses, [])
  }
}
