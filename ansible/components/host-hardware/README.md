# Component: host-hardware (layer 2)

Baremetal-only hardware setup: node-local disks, NAS NFS mounts, the
e1000e NIC-offload workaround, and the fwupd/LVFS firmware baseline.

Run after `os-baseline` (needs the `ansible` user + SSH key enrolled):

```
just host-hardware
```

## Deployment vs. component

This component never reads inventory topology. The poochella
deployment wrapper (`playbooks/poochella/infra/15-host-hardware.yml`)
computes, per host, via `set_fact`:

- `host_disks_is_hypervisor` — from `inventory_hostname in groups['hypervisors']`
- `nfs_mounts_server` — from `hostvars['nas01'].ansible_host`

before importing this component's `site.yml`. `storage.disks`,
`nfs_mounts`, and `disable_nic_offloads` are plain host/group vars
resolved through normal inventory precedence (not topology lookups),
so they need no wrapper computation — see inventory.yaml.

## Roles

| role | guarantees | unapply |
|---|---|---|
| `host-disks` | Disk -> LVM-thin -> (PVE storage \| ext4 mount) realisation from `storage.disks`, per its own `host_disks_action` dispatcher | `host_disks_action: skip` — a 3-way dispatcher (info/overwrite/skip), not a binary enable/disable |
| `nfs-mounts` (shared, `ansible/roles/`) | Mounts nas01 shares declared in `nfs_mounts` | Additive only — remove an entry and re-apply to stop managing it (does not unmount) |
| `nic-offload` | Disables TX offloads + EEE on driver-matched NICs (works around the e1000e "Detected Hardware Unit Hang") | `nic_offload_tuning_enabled: false` reverts; the host-level `disable_nic_offloads` gate (site.yml `when:`) skips the role entirely |
| `firmware` | fwupd installed, LVFS remote enabled | `firmware_enabled: false` apt-removes fwupd |

## Pre-conditions

- `os-baseline` has applied (the `ansible` user + SSH key exist).
- `nas` has applied (NFS shares must exist on nas01 before
  `nfs-mounts` can mount them).
- `storage.disks` declared per host in inventory.yaml for `host-disks`
  to do anything (hosts without it are skipped cleanly).

## Notes

- `nfs-mounts` is a shared top-level role (`ansible/roles/`), not owned
  by this component — the `30-guests` deployment tier also mounts NFS
  shares onto `kube_control_plane` VMs with the same role
  (docs/ansible-layout.md's "shared logic" rule).
- `just disk-plan` targets only the `storage` tag with
  `-e host_disks_action=info`, so it stays read-only even though the
  rest of this component's plays are not (nfs-mounts/nic-offload/
  firmware do install/mount things on a normal apply).
