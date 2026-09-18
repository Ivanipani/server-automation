# Component: kube (layer 4)

K3s with embedded etcd, kube-vip, Longhorn consumer prerequisites, and Flux.

```sh
just kube
just kube --tags k3s --limit metal-home-02
just kube --tags flux
just kube --tags firewall
just kube-verify
```

Firewall policy remains opt-in (`--tags firewall`), with the existing `40-kube`
rule ownership scope. The shared `firewall-basic` role stays in `ansible/roles`.

## Roles

| Role | Guarantee | Unapply |
|---|---|---|
| `longhorn-host-prep` | iSCSI/NFS clients, persistent `iscsi_tcp`, running iscsid | `longhorn_host_prep_enabled=false` stops iSCSI units, unloads the module, removes open-iscsi; shared nfs-common remains |
| `k3s` | Stable bootstrap, serial server joins, agents, labels, kubeconfig, optional snapshot mirror | `k3s_enabled=false` runs the upstream uninstaller and removes the snapshot sidecar, installer, and managed sysctl file |
| `flux` | Flux bootstrap and optional SOPS/apps-repository secrets | `flux_enabled=false` removes Flux controllers, CRDs, and namespace; committed manifests remain |

Unapply Flux while the API is still available, then K3s, then Longhorn prerequisites:

```sh
just kube --tags flux -e flux_enabled=false
just kube --tags k3s -e k3s_enabled=false
just kube --tags longhorn -e longhorn_host_prep_enabled=false
```

These commands change live infrastructure. K3s uninstall removes local cluster data;
Longhorn prerequisites must only be removed after dependent workloads are stopped.
The legacy `k3s_enable` switch remains supported. K3s host settings (swap policy,
loaded shared kernel modules) and shared packages are not restored by uninstall.

## Deployment vs. component

`playbooks/poochella/infra/40-kube.yml` computes server/agent identity and the full
cluster host lists, and supplies repository URLs, secrets, and snapshot policy.
The component reads no inventory topology. `kube_hosts` selects node targets;
`kube_flux_hosts` selects the controller (default localhost).

For another deployment, supply `k3s_first_server`, `k3s_first_server_address`,
`k3s_control_planes`, `k3s_ca_nodes`, and per-host `k3s_node_role` (`server` or
`agent`). The bootstrap host must come from the full deployment, never the limited
run. Missing topology fails before K3s installation. Role defaults and argument
specs document the remaining inputs; invoke `site.yml` for the ordered phases.

The CA gate probes the complete supplied node list even under `--limit`. A
mismatch fails the run before K3s changes. `k3s_reset_stale_agents=true` permits
agent cache resets only; divergent control planes require manual recovery.
A limited join requires an existing healthy API. Excluding the first server
skips kubeconfig refresh; excluding localhost skips Flux.

## Preconditions and verification

- Apply `control-node` and `host-base`; nodes must support apt/systemd and be
  reachable over SSH with privilege escalation. CA probes need all declared nodes.
- Supply `k3s_cluster_token` (poochella uses `vault_k3s_cluster_token`).
- Configure a reachable API endpoint; kube-vip needs a free address on the servers' L2 network.
- When snapshot mirroring is enabled, mount `k3s_snapshot_sync_path` first
  (poochella uses the NAS-backed `/mnt/nas/k3s-snapshots`). Backup copies remain on uninstall.
- Flux needs `flux`, `kubectl`, a fetched kubeconfig, and a writable repository SSH
  key. Poochella uses `vault_server_automation_deploy_key`, optionally
  `vault_sops_age_key` and `vault_doghouse_apps_deploy_key`.
- Flux bootstrap commits and pushes its generated manifests when applied.

`tests/verify.yml` only reads service/module state, server API readiness, and Flux
controller availability. It does not install, repair, or bootstrap anything.
