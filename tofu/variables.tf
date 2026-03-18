variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy resources on"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init and container access"
  type        = string
}

variable "template_vm_id" {
  description = "VM template ID to clone from"
  type        = number
}

variable "template_ct_id" {
  description = "LXC container template ID to clone from"
  type        = number
}

variable "vms" {
  description = "Map of VMs to create"
  type = map(object({
    hostname   = string
    cores      = optional(number, 2)
    memory     = optional(number, 2048)
    disk_size  = optional(number, 20)
    ip_address = optional(string, "dhcp")
    gateway    = optional(string, "")
    tags       = optional(list(string), [])
  }))
  default = {}
}

variable "containers" {
  description = "Map of LXC containers to create"
  type = map(object({
    hostname     = string
    cores        = optional(number, 1)
    memory       = optional(number, 512)
    swap         = optional(number, 512)
    disk_size    = optional(number, 8)
    ip_address   = optional(string, "dhcp")
    gateway      = optional(string, "")
    unprivileged = optional(bool, true)
    tags         = optional(list(string), [])
  }))
  default = {}
}
