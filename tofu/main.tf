# One `vm` and (where the inventory has any) `infra_lxcs` module
# instance per Proxmox node, each wired to that node's aliased provider
# (provider.tf) and fed only the guests pinned to it (locals).
# Standalone hypervisors don't share an API: a VM on hypervisor-B
# must be created through hypervisor-B's own provider — the
# module-per-node split is what makes that possible (Terraform won't
# let `providers` be selected dynamically inside a single resource).
# Today only pve-home-01 is a hypervisor; the shape stays
# multi-module-ready so adding a second hypervisor is purely the
# 3-step checklist in tofu/provider.tf.
#
# **Ordering invariant**: each `vms_<node>` module declares
# `depends_on = [module.infra_lxcs_<node>]`, so infra LXCs come up
# before any VM in the same `tofu apply`. This is what lets a fresh
# fleet bootstrap from one Proxmox host + router + switch in a single
# `tofu apply` — a future CP VM or worker VM that references bootserv01
# (image hosting, netboot, etc.) can assume it is already up. (We
# could broaden the dependency to "all infra modules across all
# nodes"; per-node is the conservative version that's correct as long
# as the cross-node fan-in is "infra-on-A is sufficient for VMs-on-A",
# which holds for bootserv since DNS resolves it on the LAN.)
#
# Adding a node: see the checklist in tofu/provider.tf.

module "infra_lxcs_pve_home_01" {
  source    = "./modules/lxc"
  lxcs      = local.infra_lxcs_by_node["pve-home-01"]
  providers = { proxmox = proxmox.pve_home_01 }
}

module "vms_pve_home_01" {
  source    = "./modules/vm"
  vms       = local.vms_by_node["pve-home-01"]
  providers = { proxmox = proxmox.pve_home_01 }

  depends_on = [module.infra_lxcs_pve_home_01]
}
