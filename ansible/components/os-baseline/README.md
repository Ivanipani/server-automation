# Component: os-baseline (layer 1)

Baseline every Linux host gets, physical or virtual: the
ansible/pani/tourmanager users, a locked root account, key-only sshd
with a password break-glass, a default-deny firewall, and the dynamic
poochella MOTD.

Run after `control-node` and before anything that needs to SSH as the
`ansible` user:

```
just os-baseline
```

## Deployment vs. component

This component never reads inventory topology. The poochella
deployment wrapper (`playbooks/poochella/infra/14-os-baseline.yml`)
computes `host_base_pve_host` per host from group membership
(`inventory_hostname in groups['hypervisors']`) via `set_fact` before
importing this component's `site.yml`. Pointing this component at a
different host or fleet means writing a different deployment wrapper,
not editing anything under `roles/`.

## Roles

| role | guarantees | unapply |
|---|---|---|
| `ssh-bootstrap-detect` (shared, `ansible/roles/`) | Probes whether the `ansible` user can already SSH in; falls back to `root` | n/a — probe only |
| `host-base` | hostname/`/etc/hosts` hygiene, apt-daily disabled, sudo+zsh, `host_base_users` created, root locked, PVE break-glass web-UI registration + enterprise-repo cleanup (hypervisors) or Proxmox-key/pin (workers), `proxmox-auto-install-assistant` installed | No single flag — see `meta/main.yml`; removing a user from `host_base_users` doesn't retroactively delete it (matches `create-user`'s additive convention) |
| `ssh-hardening` | Drops `10-hardening.conf`: key-only sshd except the `image_baseline_sshd.password_breakglass_user` Match block | No single flag — a reconciliation role like `synology-dsm`; edit `image_baseline_sshd` and re-apply |
| `firewall-basic` (shared, `ansible/roles/`) | Default-deny inbound ufw + `firewall_inbound_allow` | Reconciled — remove an entry and re-apply to close it |
| `motd` (shared, `ansible/roles/`) | Dynamic poochella MOTD | `motd_enabled: false` |

## Pre-conditions

- `control-node` has applied (vaulted `ansible` keypair staged).
- `host_root_pass` (group_vars/all/vars.yml) matches the PVE
  auto-installer answerfile's root password, for the first-boot
  fallback path on fresh hypervisors.

## Notes

- `ssh-bootstrap-detect` and `firewall-basic` and `motd` are shared
  top-level roles (`ansible/roles/`), not owned by this component —
  `firewall-basic` is also used by the `30-guests`/`40-kube`
  deployment tiers and `motd` by `30-guests`, so they can't live under
  a single component's `roles/` without duplicating them elsewhere
  (docs/ansible-layout.md's "shared logic" rule).
- `firewall_basic_scope` stays `17-host` (the pre-migration tier name)
  rather than `os-baseline` — see the comment in `site.yml`.
