# Per-hypervisor Tofu workspace for the standalone PVE node `pve-home-01`.
# Each Proxmox hypervisor in the fleet has its own directory under
# `tofu/per-node/<host>/` with its own state — there is no cross-node
# state coupling, matching the standalone-only topology of the fleet.
#
# Adding a new hypervisor:
#   1. Add the host to inventory.yaml (host entry + proxmox_endpoints +
#      template_vm_ids + template_ct_ids) and to `proxmox_api_tokens`
#      in group_vars/all/vars.yml.
#   2. `cp -r tofu/per-node/pve-home-01 tofu/per-node/<new-host>`
#   3. Edit `local.hypervisor_name` below to the new host's inventory key.
#      Nothing else changes — endpoint comes from inventory, token comes
#      from Ansible at apply time.

locals {
  hypervisor_name = "pve-home-01"

  # Inventory is the single source of truth for the API endpoint.
  inventory = yamldecode(file("${path.module}/../../../ansible/inventory.yaml"))
  endpoint  = local.inventory.all.vars.proxmox_endpoints[local.hypervisor_name]
}

module "hypervisor" {
  source          = "../../modules/hypervisor"
  hypervisor_name = local.hypervisor_name
}
