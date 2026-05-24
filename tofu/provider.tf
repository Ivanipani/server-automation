# One aliased provider per Proxmox node.
#
# Independent (non-clustered) hypervisors do not share an API:
# hypervisor-A's endpoint cannot create a VM on hypervisor-B. So every
# node gets its own aliased provider, and tofu/main.tf wires each
# per-node `vm` module to the matching alias. This is also correct for
# cluster members (each member exposes the full API), so one structure
# serves both topologies.
#
# Terraform cannot generate provider blocks from data — they must be
# static. Adding a node is a 4-step checklist:
#   1. inventory.yaml all.vars.{proxmox_endpoints,template_vm_ids,template_ct_ids}: add the node
#   2. tofu/variables.tf: add proxmox_api_token_<node>
#   3. here: add a provider block referencing both
#   4. tofu/main.tf: add BOTH module calls wired to the new alias —
#      `infra_lxcs_<node>` (LXC module) AND `vms_<node>` (VM module
#      with `depends_on = [module.infra_lxcs_<node>]` to keep the
#      bootstrap invariant).

provider "proxmox" {
  alias     = "pve_home_01"
  endpoint  = local.proxmox_endpoints["pve-home-01"]
  api_token = var.proxmox_api_token_pve_home_01
  insecure  = true

  ssh {
    agent = true
  }
}
