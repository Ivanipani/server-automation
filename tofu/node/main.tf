# Single FLAT Tofu root for the whole Proxmox fleet. One config — NO
# per-host directory copies. To talk to a different hypervisor you point
# `var.proxmox_endpoint` at a different URL; you do NOT `cp -r` a folder.
#
# State isolation (the standalone-PVE invariant: no shared API, no shared
# state) is provided by NAMED TOFU WORKSPACES instead of separate dirs.
# One workspace per hypervisor, named after its inventory hostname; its
# state lives under `terraform.tfstate.d/<workspace>/terraform.tfstate`.
#
# Talk to a hypervisor manually:
#   cd tofu/node
#   tofu workspace select pve-home-01     # or `tofu workspace new` first
#   export TF_VAR_proxmox_password="<advanceteam@pve password>"
#   tofu apply -var 'proxmox_endpoint=https://pve-home-01.lan:8006'
# (The Ansible drivers pass workspace + proxmox_endpoint + hypervisor_name
#  automatically — see 30-guests/10-opentofu.yml and
#  13-foundation/80-tofu-infra-lxcs.yml.)
#
# Adding a hypervisor needs NO new directory and NO new secret:
#   1. Add it to inventory.yaml (host entry + proxmox_endpoints +
#      template_vm_ids + template_ct_ids).
#   2. That's it — the Ansible drivers loop the `hypervisors` group, so a
#      fresh `tofu workspace` is created for it on first apply. The shared
#      advanceteam@pve account already authenticates everywhere.

locals {
  inventory = yamldecode(file("${path.module}/../../ansible/inventory.yaml"))

  # Which inventory node to provision. Slices the inventory walk + the
  # template-id lookups in modules/hypervisor. Defaults to the tofu
  # workspace name, so `tofu workspace select <node>` is enough for
  # manual use; Ansible passes it explicitly.
  hypervisor_name = coalesce(var.hypervisor_name, terraform.workspace)

  # The Proxmox API URL. The flat root's PRIMARY input is
  # var.proxmox_endpoint (the URL the caller points at the target node);
  # falls back to the inventory map keyed by hypervisor_name for manual
  # convenience when the URL isn't supplied.
  endpoint = coalesce(
    var.proxmox_endpoint,
    try(local.inventory.all.vars.proxmox_endpoints[local.hypervisor_name], ""),
  )
}

module "hypervisor" {
  source          = "../modules/hypervisor"
  hypervisor_name = local.hypervisor_name
}
