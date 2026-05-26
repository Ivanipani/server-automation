output "vm_ips" {
  description = "IP addresses of VMs provisioned on this hypervisor."
  value       = module.hypervisor.vm_ips
}
