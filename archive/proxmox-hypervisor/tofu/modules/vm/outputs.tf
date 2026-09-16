output "vm_ips" {
  description = "VM name => discovered IPv4 addresses for this node"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => vm.ipv4_addresses
  }
}
