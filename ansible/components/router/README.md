# Component: router (layer 3)

OPNsense: the LAN's DHCP+DNS+PXE server, tailnet subnet router, and a
node_exporter target. Every other fleet host resolves names and gets its
address from this box, so it must be fully configured before any other
physical host is provisioned.

Run it first, before any other component that targets fleet hardware:

```
just router
```

## Deployment vs. component

This component never reads inventory topology. The poochella deployment
wrapper (`playbooks/poochella/infra/10-router.yml`) builds the
poochella-specific desired state from inventory hostvars — the DHCP
static-lease list, the Unbound host-override list, the PXE toggle/TFTP
servername — and hands it in as plain vars before importing this
component's `site.yml`. Pointing this component at a different DHCP
range or DNS record set means writing a different deployment wrapper,
not editing anything under `roles/`.

## Roles

Every plugin-installing role splits `install.yml`/`uninstall.yml` (or
`configure.yml`/`deconfigure.yml`) so that flipping its `_enabled` flag
off leaves the router in a genuinely clean state — package removed,
service stopped — not just skipped. Each install role's `uninstall.yml`
stops its own daemon via raw rc.d before deleting the package, so it
doesn't depend on the sibling configure role's API-based deconfigure
having run (the API stops existing the moment the package is gone).

| role | guarantees | unapply |
|---|---|---|
| `router-bootstrap` | `ansible` user + group + SSH key + passwordless sudo on OPNsense (FreeBSD, raw commands) | `router_bootstrap_enabled: false` removes user/group/sudoers |
| `opnsense-dnsmasq` | dnsmasq general settings, DHCP range, static DHCP+DNS reservations, optional PXE chainload/dispatch rules; reconciles (deletes) stale reservations | `dnsmasq_enabled: false` disables the plugin declaratively |
| `opnsense-unbound` | Applies + reconciles Unbound host overrides (wildcard ingress, pinned service IPs, apiserver VIP) | Remove entries from `unbound_host_overrides`; orphan cleanup deletes them |
| `opnsense-tailscale-install` / `-configure` | Installs the os-tailscale plugin, configures + brings up the tailnet subnet router | `opnsense_tailscale_enabled: false` on both roles: configure disables via API, install removes the package |
| `opnsense-node-exporter-install` / `-configure` | Installs + configures the os-node_exporter plugin (Prometheus scrape target on :9100) | `opnsense_node_exporter_enabled: false` on both roles |

## Pre-conditions

- `vault_opnsense_api_key` / `vault_opnsense_api_secret` in the vault
  (OPNsense GUI: System → Access → Users → API keys → +).
- `vault_opnsense_tailscale_auth_key` in the vault for the tailscale
  roles — see `opnsense-tailscale-configure`'s argument_specs for how
  to mint one.
- `router-bootstrap` must run once (SSH as root with the vault
  password) before any of the API-driven roles can authenticate as the
  `ansible` user for their own SSH-based install phases.

## Notes

- `router-bootstrap` and the two `-install` roles talk to OPNsense over
  raw SSH (FreeBSD has no Python) with `become: true`. `opnsense-dnsmasq`,
  `opnsense-unbound`, and the two `-configure` roles run over
  `connection: local` against the OPNsense REST API — see `site.yml`
  for why each phase needs its own play.
- OPNsense's Usermanager API refuses edits to the authenticated root
  account, so managing the router root password stays a manual,
  out-of-IaC concern (console / supported path).
