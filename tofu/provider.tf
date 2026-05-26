# One aliased provider per Proxmox node.
#
# Every Proxmox hypervisor in this repo is a fully standalone PVE host
# (no corosync, no shared storage). A node's endpoint cannot create
# guests on a peer, so every node gets its own aliased provider, and
# tofu/main.tf wires each per-node module (vms_<node>, infra_lxcs_<node>)
# to the matching alias.
#
# Tokens are looked up from the `proxmox_api_tokens` map variable
# (tofu/variables.tf), which Ansible supplies at apply time as a single
# JSON-encoded `TF_VAR_proxmox_api_tokens` env var — sourced from
# `proxmox_api_tokens` in group_vars/all/vars.yml. Keys in that map MUST
# match the keys in inventory.yaml's all.vars.proxmox_endpoints.
#
# Terraform cannot generate provider blocks from data — they must be
# static. Adding a hypervisor is a 3-step checklist:
#   1. inventory.yaml all.vars.{proxmox_endpoints,template_vm_ids,template_ct_ids}: add the node;
#      group_vars/all/vars.yml `proxmox_api_tokens`: add the node's vault key
#   2. here: add a provider block (alias + endpoint + token lookup)
#   3. tofu/main.tf: add BOTH module calls wired to the new alias —
#      `infra_lxcs_<node>` (LXC module) AND `vms_<node>` (VM module
#      with `depends_on = [module.infra_lxcs_<node>]` to keep the
#      bootstrap invariant).

provider "proxmox" {
  alias     = "pve_home_01"
  endpoint  = local.proxmox_endpoints["pve-home-01"]
  api_token = var.proxmox_api_tokens["pve-home-01"]
  insecure  = true

  ssh {
    agent = true
  }
}
