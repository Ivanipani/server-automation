output "vm_ips" {
  description = "IP addresses of VMs provisioned on the selected hypervisor."
  value       = module.hypervisor.vm_ips
}
