# One aliased provider per Proxmox node.
#
# Independent (non-clustered) nodes do not share an API: pve-home-01's
# endpoint cannot create a VM on pve-home-02. So every node gets its own
# aliased provider, and tofu/main.tf wires each per-node `vm` module to
# the matching alias. This is also correct for cluster members (each
# member exposes the full API), so one structure serves both topologies.
#
# Terraform cannot generate provider blocks from data — they must be
# static. Adding a node is a 4-step checklist:
#   1. inventory.yaml all.vars.proxmox_endpoints: add the node
#   2. tofu/variables.tf: add proxmox_api_token_<node>
#   3. here: add a provider block referencing both
#   4. tofu/main.tf: add a module call wired to the new alias

provider "proxmox" {
  alias     = "pve_home_01"
  endpoint  = local.proxmox_endpoints["pve-home-01"]
  api_token = var.proxmox_api_token_pve_home_01
  insecure  = true

  ssh {
    agent = true
  }
}

provider "proxmox" {
  alias     = "pve_home_02"
  endpoint  = local.proxmox_endpoints["pve-home-02"]
  api_token = var.proxmox_api_token_pve_home_02
  insecure  = true

  ssh {
    agent = true
  }
}
