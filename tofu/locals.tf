# Read the repo-root inventory.yaml and shape the entries into the `vms` map
# consumed by proxmox_virtual_environment_vm. Every host with a `vm:` block
# becomes a VM; its declared `mac_address` is set on the NIC so dnsmasq's
# static reservation (pushed from the same file by 01b-router-dnsmasq.yml)
# lands the VM on its reserved IP at first boot.
#
# Terraform has no recursion, so we walk the inventory tree explicitly.
# The deepest path in this repo is 2 levels of `children` (kubernetes →
# kube_control_plane.hosts.<name>). Bumping the depth means adding another
# pair of _groups_l*/_hosts_l* locals here.

locals {
  inventory = yamldecode(file("${path.module}/../inventory.yaml"))

  # Provider + template config also lives in inventory.yaml's `all.vars`
  # (single source of truth shared with Ansible). Per-VM `vm.template_id`
  # overrides the computed per-node template id below.
  proxmox_endpoint           = local.inventory.all.vars.proxmox_endpoint
  template_vm_id             = local.inventory.all.vars.template_vm_id
  template_ct_id             = local.inventory.all.vars.template_ct_id
  template_vm_id_node_stride = local.inventory.all.vars.template_vm_id_node_stride

  # VM storage is node-local LVM-thin: every baremetal node builds its
  # own template with a per-node-unique id (base + node_index * stride),
  # and each VM is cloned locally on its own node from that template.
  # keys() is sorted, so pve-home-01→0, pve-home-02→1, pve-home-03→2 —
  # this MUST match the index 04-prepare-templates.yml derives from
  # `groups['baremetal']`.
  baremetal_nodes = keys(local.inventory.baremetal.hosts)
  node_index      = { for i, n in local.baremetal_nodes : n => i }

  # Top-level groups (router, baremetal, switches, virtual-machines, kubernetes, ...)
  _groups_l1 = { for k, v in local.inventory : k => v if k != "all" && can(v) && v != null }
  _hosts_l1  = merge({}, [for g in local._groups_l1 : try(g.hosts, {})]...)

  # children of those groups (e.g. virtual-machines → databases, kubernetes)
  _groups_l2 = merge({}, [for g in local._groups_l1 : try(g.children, {})]...)
  _hosts_l2  = merge({}, [for g in local._groups_l2 : try(g.hosts, {})]...)

  # children-of-children (e.g. kubernetes.children.kube_control_plane.hosts)
  _groups_l3 = merge({}, [for g in local._groups_l2 : try(g.children, {})]...)
  _hosts_l3  = merge({}, [for g in local._groups_l3 : try(g.hosts, {})]...)

  all_hosts = merge(local._hosts_l1, local._hosts_l2, local._hosts_l3)

  vms_from_inventory = {
    for name, h in local.all_hosts : name => {
      hostname       = name
      mac_address    = h.mac_address
      cores          = try(h.vm.cores, 2)
      memory         = try(h.vm.memory, 2048)
      disk_size      = try(h.vm.disk_size, 20)
      data_disk_size = try(h.vm.data_disk_size, 0)
      ip_address     = "dhcp"
      gateway        = ""
      tags           = try(h.vm.tags, [])
      node           = h.vm.proxmox_node
      # Per-VM override wins; otherwise base + this node's offset.
      template_id = try(
        h.vm.template_id,
        local.template_vm_id + local.node_index[h.vm.proxmox_node] * local.template_vm_id_node_stride,
      )
    } if try(h.vm, null) != null
  }
}
