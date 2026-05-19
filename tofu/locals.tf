# Read the repo-root inventory.yaml and shape the entries into the `vms` map
# consumed by the per-node `vm` module. Every host with a `vm:` block
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
  # (single source of truth shared with Ansible). VM storage is
  # node-local LVM-thin, so each baremetal node has its own template with
  # a distinct VMID. `template_vm_ids` is an explicit {node => anchor id}
  # map (no offset math, no group-ordering coupling); the anchor is the
  # node's default/first VM template, which is exactly what each VM is
  # cloned from. Per-VM `vm.template_id` overrides it. `proxmox_endpoints`
  # is {node => API endpoint} — one aliased provider per node lives in
  # provider.tf (independent nodes don't share an API).
  proxmox_endpoints = local.inventory.all.vars.proxmox_endpoints
  template_vm_ids   = local.inventory.all.vars.template_vm_ids

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
      # Per-VM override wins; otherwise this node's anchor template.
      template_id = try(h.vm.template_id, local.template_vm_ids[h.vm.proxmox_node])
    } if try(h.vm, null) != null
  }

  # Partition the VM map by target node so each per-node `vm` module
  # (tofu/main.tf) only sees — and only its node's provider touches —
  # the VMs pinned to it. A node with no VMs gets an empty map (the
  # module then creates nothing).
  vms_by_node = {
    for node in keys(local.proxmox_endpoints) : node => {
      for name, vm in local.vms_from_inventory : name => vm if vm.node == node
    }
  }
}
