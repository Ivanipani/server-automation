# Component: nas (layer 3)

Synology DSM (nas01): the fleet's NFS/SMB/rsync file server. Every data
path (Longhorn backups, VM /home, PXE artifacts, qcow2 image publish)
rides NFS off this box.

Run after the router component (needs its DNS+DHCP reservation) and
before any component that mounts a share:

```
just nas
```

## Deployment vs. component

This component never reads inventory topology. The poochella
deployment wrapper (`playbooks/poochella/infra/12-nas.yml`) computes
the storage desired state (`synology_storage_vol_path`,
`synology_storage_shares`) from inventory's `storage:` host block via
`set_fact`, and supplies the poochella-specific service toggles
(NFSv4 on for Longhorn, SMB on, SSH on as break-glass, User Home
Service on for pani, etc.) as plain vars before importing this
component's `site.yml`. Pointing this component at a different DSM box
or a different set of shares means writing a different deployment
wrapper, not editing anything under `roles/`.

## Roles

| role | guarantees | unapply |
|---|---|---|
| `synology-dsm` | Terminal (SSH/Telnet), NFS/SMB/rsync file services, User Home Service (opt-in), package sources — all via DSM's JSON API | Each service toggle is independently reversible (e.g. `synology_dsm_nfs_enable: false`); no single role-wide flag since the role only configures services DSM already ships |
| `synology-storage` | Creates shares declared in `synology_storage_shares` that are missing on DSM, corrects drifted quotas, (re)saves NFS export rules | Additive only — remove a share from the list to stop managing it, but the role never deletes it from DSM (see `tasks/shares.yml`) |
| `synology-ssh-access` | Installs the controller's pubkey into pani's `authorized_keys` (idempotent, raw SSH — DSM has no guaranteed system Python) | `synology_ssh_access_enabled: false` removes the key |

## Pre-conditions

- `vault_synology_dsm_password` in the vault, wired to
  `synology_dsm_password` in `group_vars/all/vars.yml` (already done).
- A DSM administrator account (`pani` in poochella) exists with no 2FA
  — see `roles/synology-dsm/README.md` for the one-time DSM-side setup
  this component does NOT automate.
- `synology-dsm` must apply with `synology_dsm_manage_user_home_service:
  true` before `synology-ssh-access` can succeed — pani needs a real
  `$HOME` on `/volume1` for `.ssh/authorized_keys` to land in.

## Notes

- `synology-dsm` and `synology-storage` both run over `connection:
  local` against DSM's REST API (never SSH). `synology-ssh-access` is
  the one exception — see `site.yml` for why it needs its own play.
- Pool/volume create/destroy stays a manual DSM Storage Manager UI
  operation by design — see `synology-storage`'s role README /
  `tasks/main.yml` header.
