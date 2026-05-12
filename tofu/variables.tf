variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

# variable "containers" {
#   description = "Map of LXC containers to create"
#   type = map(object({
#     hostname     = string
#     cores        = optional(number, 1)
#     memory       = optional(number, 512)
#     swap         = optional(number, 512)
#     disk_size    = optional(number, 8)
#     ip_address   = optional(string, "dhcp")
#     gateway      = optional(string, "")
#     unprivileged = optional(bool, true)
#     tags         = optional(list(string), [])
#   }))
#   default = {}
# }
