# One Proxmox node's LXCs. Instantiated once per node by tofu/main.tf
# with that node's aliased provider — same per-node-module pattern as
# tofu/modules/vm, so independent (non-clustered) nodes work the same.
#
# Each LXC is **cloned** from its node's anchor LXC template (the
# `template_ct_ids[node]` value from inventory). The clone preserves
# the bake (apt sources, ansible user, key, sysprep), then this resource
# overlays the host-specific identity (hostname, MAC, IP, resources).
# Storage is `vms` (the only per-node pve_storage with `rootdir` content
# per the storage-carving contract in inventory.yaml).

resource "proxmox_virtual_environment_container" "ct" {
  for_each = var.lxcs

  node_name    = each.value.node
  description  = each.key
  tags         = each.value.tags
  unprivileged = each.value.unprivileged
  # Start on apply + bring back up on boot of the host. Matches VM
  # behaviour: the LXC is a managed service, not an experiment.
  start_on_boot = true
  started       = true

  clone {
    vm_id = each.value.template_id
    # No `full = true` — for LXC the bpg provider defaults to a full
    # clone on local (non-shared) storage anyway, and linked clones
    # don't survive template re-bakes.
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = "vms" # node-local LVM-thin; LXC pinned to its node
    size         = each.value.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
    # No mac_address — let PVE auto-generate. The bpg provider's
    # network_interface.mac_address override doesn't actually take
    # effect on cloned containers (PVE rejects most net0 fields at
    # clone time), and we don't depend on a stable MAC anyway:
    # OPNsense's dnsmasq registers `<hostname>.lan → DHCP IP` via
    # `regdhcp: true`, so callers reach the LXC by hostname.
  }

  # `initialization` for LXC accepts hostname + (limited) ip_config on
  # clone via the bpg provider. We set ONLY `hostname` — that one
  # field maps to `pct set --hostname` which PVE applies cleanly
  # post-clone. The DHCP request the LXC fires on first boot then
  # advertises this name, so OPNsense registers `<hostname>.lan` in
  # dnsmasq's DNS table and the host is reachable by name.
  #
  # NOT included: `user_account.keys` (PVE clone API rejects
  # `ssh-public-keys` — see commit history; the Debian LXC template
  # already bakes the canonical ansible-user key, so the clone is
  # SSH-reachable without re-injection) and `ip_config` (we let DHCP
  # handle addressing; no per-LXC static-IP bookkeeping needed).
  initialization {
    hostname = each.value.hostname
  }

  features {
    nesting = each.value.nesting
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  # The clone copies the template's existing disk, so size diffs after
  # the fact would force re-clone. Match the VM module's safety net.
  lifecycle {
    ignore_changes = [disk]
  }
}
