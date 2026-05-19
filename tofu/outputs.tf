output "vm_ips" {
  description = "IP addresses of provisioned VMs (merged across all nodes)"
  value = merge(
    module.vms_pve_home_01.vm_ips,
    module.vms_pve_home_02.vm_ips,
  )
}

# output "container_ips" {
#   description = "IP addresses of provisioned containers"
#   value = {
#     for name, ct in proxmox_virtual_environment_container.ct :
#     name => ct.initialization[0].ip_config[0].ipv4[0].address
#   }
# }
