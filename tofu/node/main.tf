# Single FLAT Tofu root for the whole Proxmox fleet. One config — NO
# per-host directory copies. To talk to a different hypervisor you select
# its workspace + pass hypervisor_name; you do NOT `cp -r` a folder.
#
# State isolation (the standalone-PVE invariant: no shared API, no shared
# state) is provided by NAMED TOFU WORKSPACES instead of separate dirs.
# One workspace per hypervisor, named after its inventory hostname; its
# state lives under `terraform.tfstate.d/<workspace>/terraform.tfstate`.
#
# The API URL is DERIVED by convention from the hostname
# (https://<hypervisor_name>.<domain>:8006) — there is no endpoint map.
#
# Talk to a hypervisor manually:
#   cd tofu/node
#   tofu workspace select pve-home-01     # or `tofu workspace new` first
#   export TF_VAR_proxmox_password="<advanceteam@pve password>"
#   tofu apply                            # endpoint derived from the workspace name
# (The Ansible drivers pass workspace + hypervisor_name automatically —
#  see 30-guests/10-opentofu.yml and 13-foundation/80-tofu-infra-lxcs.yml.)
#
# Adding a hypervisor needs NO new directory and NO new secret:
#   1. Add it to inventory.yaml — just the host entry. The endpoint is
#      derived from its hostname; the template anchors (template_vm_id_base
#      / template_ct_id_base) are fleet-wide scalars — nothing per-node.
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

  # The Proxmox API URL. By convention every standalone hypervisor's API
  # lives at https://<hostname>.<domain>:8006, so it's derived from
  # hypervisor_name + all.vars.domain — no per-node map to maintain.
  # var.proxmox_endpoint is an optional override (e.g. an IP or alt port
  # for manual CLI use); when empty (the Ansible-driven default) the
  # derived URL is used.
  endpoint = coalesce(
    var.proxmox_endpoint,
    "https://${local.hypervisor_name}.${local.inventory.all.vars.domain}:8006",
  )
}

module "hypervisor" {
  source          = "../modules/hypervisor"
  hypervisor_name = local.hypervisor_name
}
