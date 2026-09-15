# Component: observability (layer 2)

Installs and runs Prometheus node_exporter, giving every host a scrape
target on port 9100.

```
just observability
```

## Deployment vs. component

This component never reads inventory topology — `node_exporter_enabled`
is a plain group/host var. No deployment wrapper computation is needed
beyond the target group.

## Roles

| role | guarantees | unapply |
|---|---|---|
| `node-exporter` | node_exporter installed (upstream release tarball) and running under a dedicated system user | `node_exporter_enabled: false` stops + disables the service (binary stays installed) |

## Pre-conditions

- `os-baseline` has applied (the `ansible` user + SSH key exist).
- `firewall_inbound_allow` (managed by `os-baseline`) includes 9100/tcp
  wherever a scraper needs to reach this host.
