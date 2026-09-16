# archive/proxmox-hypervisor

Archived, not deleted. The fleet has 0 Proxmox hypervisors today — every
former PVE box (pve-home-01/02/03) was converted to baremetal
(kube-master-01/02/03) — so this code was taken out of the hot path. It
was fully functional the day it was moved here and nothing inside it was
changed beyond its location.

## What's here

| Path here | Original path |
|---|---|
| `tofu/` | `tofu/` |
| `ansible/roles/hypervisor/` | `ansible/roles/hypervisor/` |
| `ansible/playbooks/13-foundation/` | `ansible/playbooks/poochella/infra/13-foundation/` |
| `ansible/playbooks/20-hypervisor/` | `ansible/playbooks/poochella/infra/20-hypervisor/` |
| `ansible/playbooks/30-guests/` | `ansible/playbooks/poochella/infra/30-guests/` |
| `img-proxmox/` | `img/proxmox/` |
| `docs/proxmox.md` | `docs/runbooks/proxmox.md` |

`tofu/node/terraform.tfstate.d/<host>/` holds the real, last-known
per-workspace state for pve-home-01/02/03 — do not discard it if this is
ever restored; it's how Tofu would recognize those hosts' old resources
if the same physical boxes are ever re-Proxmoxed.

## Why moved, not deleted

The Proxmox-provisioning tiers ran as no-ops on every `just run` once the
`hypervisors`/`foundation` inventory groups went empty — dead weight in
the hot path, but still correct, working code that shouldn't be thrown
away in case a hypervisor comes back.

## Restore procedure

1. Move each directory in the table above back to its original path.
2. In `ansible/playbooks/poochella/infra/site.yml`, re-add:
   - `- import_playbook: 13-foundation/site.yml` (before `14-host-base.yml`)
   - `- import_playbook: 20-hypervisor/site.yml` (after `15-bootserv.yml`)
   - `- import_playbook: 30-guests/site.yml` (right after that)
3. Revert the `CLAUDE.md` Overview section's note about 0 hypervisors /
   this archive.
4. Add the host(s) back into `inventory.yaml`'s `hypervisors` (and, if it
   should gate other baremetal, `foundation`) groups.
