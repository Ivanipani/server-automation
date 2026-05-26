output "vm_ips" {
  description = "IP addresses of provisioned VMs on this hypervisor (forwarded from the vm submodule)."
  value       = module.vms.vm_ips
}
