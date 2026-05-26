# Reads the repo-root inventory.yaml and slices to the guests pinned to
# `var.hypervisor_name`. The slice feeds the per-node `vm` + `lxc`
# submodules in main.tf.
#
# Terraform has no recursion, so we walk the inventory tree explicitly.
# Deepest path in this repo is 2 levels of `children` (kubernetes →
# kube_control_plane.hosts.<name>). Bumping the depth means adding
# another pair of _groups_l*/_hosts_l* locals here.

locals {
  inventory = yamldecode(file("${path.module}/../../../ansible/inventory.yaml"))

  template_vm_ids = local.inventory.all.vars.template_vm_ids
  template_ct_ids = local.inventory.all.vars.template_ct_ids

  # Top-level groups (router, physical, hypervisors, workers, switches, virtual-machines, kubernetes, ...)
  _groups_l1 = { for k, v in local.inventory : k => v if k != "all" && can(v) && v != null }
  _hosts_l1  = merge({}, [for g in local._groups_l1 : try(g.hosts, {})]...)

  # children of those groups (e.g. virtual-machines → databases, kubernetes)
  _groups_l2 = merge({}, [for g in local._groups_l1 : try(g.children, {})]...)
  _hosts_l2  = merge({}, [for g in local._groups_l2 : try(g.hosts, {})]...)

  # children-of-children (e.g. kubernetes.children.kube_control_plane.hosts)
  _groups_l3 = merge({}, [for g in local._groups_l2 : try(g.children, {})]...)
  _hosts_l3  = merge({}, [for g in local._groups_l3 : try(g.hosts, {})]...)

  all_hosts = merge(local._hosts_l1, local._hosts_l2, local._hosts_l3)

  # Every host with a `vm:` block pinned to THIS hypervisor.
  vms_for_this_node = {
    for name, h in local.all_hosts : name => {
      hostname    = name
      mac_address = h.mac_address
      cores       = try(h.vm.cores, 2)
      memory      = try(h.vm.memory, 2048)
      disk_size   = try(h.vm.disk_size, 20)
      ip_address  = "dhcp"
      gateway     = ""
      tags        = try(h.vm.tags, [])
      node        = h.vm.proxmox_node
      # Per-VM override wins; otherwise this node's anchor template.
      template_id = try(h.vm.template_id, local.template_vm_ids[h.vm.proxmox_node])
    } if try(h.vm, null) != null && try(h.vm.proxmox_node, null) == var.hypervisor_name
  }

  # Every host with an `lxc:` block pinned to THIS hypervisor AND
  # tagged `infra`. The `infra` tag matters because main.tf creates a
  # separate `infra_lxcs` module that VMs `depends_on` — infra LXCs
  # (today: bootserv01) come up before any VM in the same apply.
  infra_lxcs_for_this_node = {
    for name, h in local.all_hosts : name => {
      hostname     = name
      cores        = try(h.lxc.cores, 1)
      memory       = try(h.lxc.memory, 512)
      swap         = try(h.lxc.swap, 512)
      disk_size    = try(h.lxc.disk_size, 8)
      unprivileged = try(h.lxc.unprivileged, true)
      nesting      = try(h.lxc.features.nesting, false)
      tags         = try(h.lxc.tags, [])
      node         = h.lxc.proxmox_node
      template_id  = try(h.lxc.template_id, local.template_ct_ids[h.lxc.proxmox_node])
    } if try(h.lxc, null) != null && try(h.lxc.proxmox_node, null) == var.hypervisor_name && contains(try(h.lxc.tags, []), "infra")
  }
}
