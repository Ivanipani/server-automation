output "vm_ips" {
  description = "IP addresses of provisioned VMs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => vm.ipv4_addresses
  }
}

output "container_ips" {
  description = "IP addresses of provisioned containers"
  value = {
    for name, ct in proxmox_virtual_environment_container.ct :
    name => ct.initialization[0].ip_config[0].ipv4[0].address
  }
}
