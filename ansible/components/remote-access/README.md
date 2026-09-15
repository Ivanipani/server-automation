# Component: remote-access (layer 2)

Installs and authenticates the Tailscale client. In poochella this is
default-off (`tailscale_enabled: false` in `group_vars/physical.yml`)
— the OPNsense subnet router (see the `router` component) already
advertises `10.1.1.0/24` into the tailnet, so per-host Tailscale is
redundant for LAN-equivalence and only adds attack surface (the daemon
punches its own accept rules into the host firewall, bypassing
`firewall-basic`'s ufw policy).

```
just remote-access
```

## Deployment vs. component

This component never reads inventory topology — `tailscale_enabled`
and `tailscale_auth_key` are plain group/host vars. No deployment
wrapper computation is needed beyond the target group.

## Roles

| role | guarantees | unapply |
|---|---|---|
| `tailscale` | tailscaled installed (upstream release tarball) and authenticated | `tailscale_enabled: false` stops + disables the service (binaries stay installed) |

## Pre-conditions

- `os-baseline` has applied (the `ansible` user + SSH key exist).
- `tailscale_auth_key` set (vault-backed) wherever `tailscale_enabled: true`.
