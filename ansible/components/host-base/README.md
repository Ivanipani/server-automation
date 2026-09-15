# Component: host-base (layer 1)

Everything a baremetal Linux host needs to be a fleet member: users,
SSH hardening, firewall, MOTD, node-local disks, NAS NFS mounts, the
e1000e NIC-offload workaround, the fwupd/LVFS firmware baseline,
Tailscale, and Prometheus node_exporter.

Run after `control-node`:

```
just host-base
```

## Deployment vs. component

This component never reads inventory topology. The poochella
deployment wrapper (`playbooks/poochella/infra/14-host-base.yml`)
computes, per host, via `set_fact`:

- `host_base_pve_host` / `host_disks_is_hypervisor` — both from
  `inventory_hostname in groups['hypervisors']`, computed once and
  assigned to both names since `host-base` and `host-disks` each
  prefix their own vars with their own role name.
- `nfs_mounts_server` — from `hostvars['nas01'].ansible_host`

before importing this component's `site.yml`. `storage.disks`,
`nfs_mounts`, and `disable_nic_offloads` are plain host/group vars
resolved through normal inventory precedence (not topology lookups),
so they need no wrapper computation — see inventory.yaml.

## Roles

| role | guarantees | unapply |
|---|---|---|
| `ssh-bootstrap-detect` (shared, `ansible/roles/`) | Probes whether the `ansible` user can already SSH in; falls back to `root` | n/a — probe only |
| `host-base` | hostname/`/etc/hosts` hygiene, apt-daily disabled, sudo+zsh, `host_base_users` created, root locked, PVE break-glass web-UI registration + enterprise-repo cleanup (hypervisors) or Proxmox-key/pin (workers), `proxmox-auto-install-assistant` installed | No single flag — see `meta/main.yml`; removing a user from `host_base_users` doesn't retroactively delete it (matches `create-user`'s additive convention) |
| `ssh-hardening` | Drops `10-hardening.conf`: key-only sshd except the `image_baseline_sshd.password_breakglass_user` Match block | No single flag — a reconciliation role like `synology-dsm`; edit `image_baseline_sshd` and re-apply |
| `firewall-basic` (shared, `ansible/roles/`) | Default-deny inbound ufw + `firewall_inbound_allow` | Reconciled — remove an entry and re-apply to close it |
| `motd` (shared, `ansible/roles/`) | Dynamic poochella MOTD | `motd_enabled: false` |
| `host-disks` | Disk -> LVM-thin -> (PVE storage \| ext4 mount) realisation from `storage.disks`, per its own `host_disks_action` dispatcher | `host_disks_action: skip` — a 3-way dispatcher (info/overwrite/skip), not a binary enable/disable |
| `nfs-mounts` (shared, `ansible/roles/`) | Mounts nas01 shares declared in `nfs_mounts` | Additive only — remove an entry and re-apply to stop managing it (does not unmount) |
| `nic-offload` | Disables TX offloads + EEE on driver-matched NICs (works around the e1000e "Detected Hardware Unit Hang") | `nic_offload_tuning_enabled: false` reverts; the host-level `disable_nic_offloads` gate (site.yml `when:`) skips the role entirely |
| `firmware` | fwupd installed, LVFS remote enabled | `firmware_enabled: false` apt-removes fwupd |
| `tailscale` | tailscaled installed (upstream release tarball) and authenticated | `tailscale_enabled: false` stops + disables the service (binaries stay installed) |
| `node-exporter` | node_exporter installed (upstream release tarball) and running under a dedicated system user | `node_exporter_enabled: false` stops + disables the service (binary stays installed) |

## Pre-conditions

- `control-node` has applied (vaulted `ansible` keypair staged).
- `host_root_pass` (group_vars/all/vars.yml) matches the PVE
  auto-installer answerfile's root password, for the first-boot
  fallback path on fresh hypervisors.
- `nas` has applied (NFS shares must exist on nas01 before
  `nfs-mounts` can mount them).
- `tailscale_auth_key` set (vault-backed) wherever `tailscale_enabled: true`.

## Notes

- `ssh-bootstrap-detect`, `firewall-basic`, `motd`, and `nfs-mounts` are
  shared top-level roles (`ansible/roles/`), not owned by this
  component — `firewall-basic`/`motd`/`nfs-mounts` are also used by the
  `30-guests`/`40-kube` deployment tiers, so they can't live under a
  single component's `roles/` without duplicating them elsewhere
  (docs/ansible-layout.md's "shared logic" rule).
- `firewall_basic_scope` stays `17-host` (the pre-migration tier name)
  rather than `host-base` — see the comment in `site.yml`.
- `just disk-plan` targets only the `storage` tag with
  `-e host_disks_action=info`, so it stays read-only even though the
  rest of this component's plays are not.
