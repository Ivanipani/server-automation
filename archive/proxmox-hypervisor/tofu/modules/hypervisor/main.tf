# Wraps the `infra_lxcs` + `vms` modules for ONE standalone Proxmox
# hypervisor. Driven from the flat `tofu/node/` root, which sets
# `hypervisor_name` and supplies the (single, non-aliased) proxmox
# provider. Each node has its own state via a named tofu workspace —
# there is no cross-hypervisor coupling at the Terraform layer.
#
# Ordering invariant: `vms` depends_on `infra_lxcs`, so infra LXCs
# (today: bootserv01) come up before any VM in the same `tofu apply`.
# Foundation tier exploits this with `-target=module.hypervisor.module.infra_lxcs`
# to bring up bootserv01 without dragging the VMs into the apply.

module "infra_lxcs" {
  source = "../lxc"
  lxcs   = local.infra_lxcs_for_this_node
}

module "vms" {
  source = "../vm"
  vms    = local.vms_for_this_node

  depends_on = [module.infra_lxcs]
}
