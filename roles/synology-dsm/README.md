# roles/synology-dsm

Declarative configuration of a Synology NAS running DSM 7.x, via the same
JSON-over-HTTP API DSM's own web UI uses. Treats the NAS like any other
managed host in poochella — credentials in the vault, vars in inventory,
state pushed by `just run`.

## Provenance + fork notes

Forked from [`agaffney/ansible-synology-dsm`](https://github.com/agaffney/ansible-synology-dsm)
(MIT, 2019). The upstream's API shape is sound, but the original had
several issues that ruled it out as a direct dependency for this repo:

- Login was a `GET` with `passwd=` in the URL query string (clear-logged
  by every proxy/access-log) and the default `base_url` was HTTP.
- No TLS verification knob, no `no_log` anywhere, no logout, default
  `password: changeme`, no 2FA support.
- DSM 7.3 removed AFP entirely — upstream's AFP block would hard-fail.

This fork lives under `roles/` so it is **ours** to evolve. See the
`tasks/*.yml` for the hardening; the upstream commit forked is the tip of
`main` as of 2026-05-21.

## Pre-requisites on the NAS

Run-once setup the role does **not** automate (control-plane chicken-and-egg
on a Synology):

1. DSM is initialised and reachable on the LAN (poochella: `nas01.lan`,
   `10.1.1.130` — see `inventory.yaml`, group `storage`).
2. A DSM administrator account exists with **no 2FA** (or pass
   `synology_dsm_otp_code` per-run). Never use the default `admin`
   account. In poochella this is `pani` (matching the homelab-wide
   user convention; password lives at `vault_pani_user_pass`'s sibling,
   `vault_synology_dsm_password`). Create it in DSM → Control Panel →
   User & Group → Create.
3. The account's password is stored in the vault as
   `vault_synology_dsm_password` and re-exported as
   `synology_dsm_password` in `group_vars/all/vars.yml` (already wired).
4. Either (a) DSM's self-signed cert is acceptable and
   `synology_dsm_validate_certs: false`, OR (b) a real cert is installed
   on DSM and the default `true` stays.

## Usage

```yaml
- hosts: nas01
  gather_facts: false
  connection: local           # we never SSH into DSM; everything is API
  roles:
    - role: synology-dsm
      vars:
        synology_dsm_username: ansible
        # synology_dsm_password comes from vault via group_vars/all/vars.yml
        synology_dsm_validate_certs: false   # self-signed default
        synology_dsm_ssh_enable: true
        synology_dsm_ssh_port: 22
        synology_dsm_nfs_enable: true        # Longhorn backup target
        synology_dsm_nfs_enable_v4: true
        synology_dsm_smb_enable: true
```

The role logs in on entry, applies state, and **always** logs out — even
on failure — so the session cookie does not outlive the run.

## What's verified on DSM 7.3.2 vs inherited from upstream

- `SYNO.API.Auth` v6 (login/logout)         — **bumped from upstream v3**
- `SYNO.Core.Terminal` v3                    — inherited (works on 7.x in testing)
- `SYNO.Core.FileServ.NFS` v2                — inherited; **verify first run**
- `SYNO.Core.FileServ.SMB` v3                — inherited
- `SYNO.Core.User.Home` v1                   — inherited
- `SYNO.Core.System.Status` v1               — inherited
- `SYNO.Core.Package.Feed` v1                — inherited
- AFP                                        — **removed** (gone in DSM 7.2+)

If something 404s, DSM's UI Network tab is the source of truth: open the
UI, do the action by hand, copy the API name/version/method from the
request, paste in here.

## Operational notes

- The action plugin `action_plugins/synology_dsm_api_request.py` is local;
  Ansible auto-loads it from the role. No `ansible.cfg` change needed.
- `no_log: true` is set on login/logout. If you need to debug a failure,
  flip it temporarily — **and never commit the change**.
- The session cookie is held in a task-scoped fact
  (`synology_dsm_login_cookie`) inside the wrapper block. It is wiped in
  the `always:` logout, but if a run is interrupted between login and
  logout the cookie idles out on DSM's side (default 30 min).
