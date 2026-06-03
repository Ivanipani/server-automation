# doghouse

Flux-managed Kubernetes cluster running on Proxmox.

## Layout

```
clusters/doghouse/          # Flux entrypoint: Kustomizations pointing at infra + apps
infrastructure/controllers/ # Platform components (Prometheus, MetalLB, exporters, ...)
infrastructure/configs/     # CRs that depend on installed controllers (IP pools, ingress config, ...)
apps/doghouse/              # Application workloads (placeholder)
```

## Bootstrap

One-time setup against a fresh cluster.

1. Create an SSH key and register the **public** half as a deploy key with **write** access on `github.com/Ivanipani/doghouse`:
   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/github -N ""
   cat ~/.ssh/github.pub  # paste into GitHub → repo → Settings → Deploy keys
   ```
2. Point `kubectl` at the cluster: `kubectl config use-context doghouse`.
3. Bootstrap Flux:
   ```sh
   just bootstrap-flux
   ```
   Flux installs itself, commits `clusters/doghouse/flux-system/` to this repo, and pushes. Run `git pull` afterwards.
4. Install the SOPS age key so Flux can decrypt secrets (see [Secrets (SOPS)](#secrets-sops)).
5. Set the real Proxmox API token value in the encrypted secret (see [Proxmox API token](#proxmox-api-token-sops-managed)). Flux then reconciles the monitoring stack automatically.

## Node scheduling model

Control-plane nodes do as little work as possible — the cluster is on a 1 GbE substrate and we don't want general workloads competing with etcd traffic. All workloads default to the worker pool; landing on a CP node is an explicit opt-in per workload.

The mechanism is the standard `node-role.kubernetes.io/control-plane=:NoSchedule` taint (the kubeadm convention), applied at the k3s level so it survives node rebuilds:

```yaml
# /etc/rancher/k3s/config.yaml on each CP node — managed in the Ansible repo,
# group_vars/kube_control_plane.yml. The taint is born with the node; do not
# `kubectl taint` it imperatively.
node-taint:
  - "node-role.kubernetes.io/control-plane=:NoSchedule"
```

**Greenfield order matters:** apply the taint via Ansible *before* bootstrapping Flux. Taints are not retroactive for `NoSchedule`, so anything already scheduled on CP stays put until it's rescheduled.

The same `config.yaml` should also disable the k3s-shipped `local-path` StorageClass, so Longhorn can be the sole default (otherwise k3s re-applies `storageclass.kubernetes.io/is-default-class: "true"` on local-path on every k3s restart and you end up with two defaults):

```yaml
# /etc/rancher/k3s/config.yaml on CP nodes (Ansible-managed)
disable:
  - local-storage
```

What runs on CP under this model, and why:

| Workload                                  | On CP? | Reason                                                                                                              |
|-------------------------------------------|--------|---------------------------------------------------------------------------------------------------------------------|
| etcd, kube-apiserver, controller-manager, scheduler | yes    | k3s server components; run as part of k3s itself, not as scheduled pods.                                            |
| kube-vip                                  | yes    | Holds the API VIP — must be on CP nodes. DaemonSet has CP toleration in the Ansible-applied manifest.               |
| CoreDNS, metrics-server, svclb-traefik    | yes    | k3s built-ins; ship with CP tolerations upstream.                                                                   |
| prometheus-node-exporter (DS)             | yes    | Wants per-node metrics from every node, including CP. Chart default tolerates everything.                           |
| metallb-speaker (DS)                      | yes    | L2 ARP announcer; needs to run on any node that could win the election. Chart default tolerates CP.                 |
| longhorn-manager + csi-plugin (DS)        | yes    | Tolerations set explicitly in `infra/storage/longhorn/release.yaml` so the CSI plane is available if we ever pin a Longhorn-PVC workload to CP. **No replica data** lands on CP — gated by `node.longhorn.io/create-default-disk` (workers only). |
| Traefik (Deployment, not svclb)           | no     | Chart default has no CP toleration; lands on a worker.                                                              |
| Flux controllers                          | no     | Default manifests have no CP toleration.                                                                            |
| Prometheus, Grafana, Alertmanager, kube-state-metrics, prometheus-operator | no     | Chart defaults; all land on workers.                                                                                |
| Longhorn UI / driver Deployment           | no     | Chart defaults.                                                                                                     |
| Headlamp                                  | no     | Chart default.                                                                                                      |

**Adding a workload to CP later.** Add a toleration to its pod spec (or chart values):

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

If the workload should *only* run on CP, pair it with a `nodeAffinity` on `node-role.kubernetes.io/control-plane`.

**Pre-flight check before tainting** an existing CP node: confirm kube-vip's DaemonSet has the toleration (`kubectl -n kube-system get ds kube-vip-ds -o yaml | grep -A6 tolerations`). Without it, kube-vip stops scheduling and the API VIP goes with it.

## Secrets (SOPS)

Secrets are committed to this repo encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age). Only the `data` / `stringData` fields are encrypted (config in `.sops.yaml`), so the rest of each manifest stays diff-able. Flux's `kustomize-controller` decrypts them in-cluster using the age private key — wired via `spec.decryption` on the `infrastructure` Kustomization (`clusters/doghouse/infrastructure.yaml`).

The age **public** key lives in `.sops.yaml`. The **private** key must never be committed (`age.agekey` is git-ignored) and is bootstrapped into the cluster once:

```sh
# Generate the key pair once (keep age.agekey somewhere safe — a password
# manager — losing it means no committed secret can ever be decrypted again):
age-keygen -o age.agekey

# Load the private half into the cluster so kustomize-controller can decrypt:
cat age.agekey | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin
```

To author a new encrypted secret, name the file `*.sops.yaml`, write the plaintext `Secret`, then encrypt in place before committing:

```sh
sops -e -i path/to/whatever.sops.yaml
# decrypt locally (needs the private key):
SOPS_AGE_KEY_FILE=age.agekey sops -d path/to/whatever.sops.yaml
```

## Proxmox API token (SOPS-managed)

`prometheus-pve-exporter` needs an API token to talk to PVE. The Secret lives encrypted in this repo at `infrastructure/controllers/kube-prometheus-stack/pve-exporter-token.sops.yaml` and is decrypted in-cluster by Flux (see [Secrets (SOPS)](#secrets-sops)).

On Proxmox: Datacenter → Permissions → API Tokens → Add. Recommended setup:
- User: dedicated `monitoring@pve` with role `PVEAuditor` on path `/`.
- Token ID: `prometheus`.
- Uncheck **Privilege Separation** for the simplest path.
- Copy the secret value — it's only shown once.

The committed file ships with a `REPLACE_WITH_PVE_API_TOKEN_UUID` placeholder. Set the real value in place (opens the decrypted Secret in `$EDITOR`, re-encrypts on save — needs the age private key):
```sh
SOPS_AGE_KEY_FILE=age.agekey sops infrastructure/controllers/kube-prometheus-stack/pve-exporter-token.sops.yaml
```
Replace the placeholder under `stringData.tokenValue`, save, then commit the re-encrypted file. Flux applies and prunes it like any other tracked resource — no manual re-run after a cluster rebuild.

Also update the host address lists in two places before committing:
- `infrastructure/controllers/prometheus-pve-exporter/release.yaml` → `pveTargets` (for the PVE API exporter).
- `infrastructure/controllers/kube-prometheus-stack/release.yaml` → `additionalScrapeConfigs[].static_configs[].targets` (for the bare-metal `node-exporter` installed on each Proxmox host via Ansible — port `9100`).

## Accessing the monitoring UIs

All three services are fronted by the k3s-shipped Traefik ingress, pinned to `10.1.1.250` via MetalLB. Once the corresponding DNS entries exist on the LAN (managed in OPNsense via Ansible), reach them directly:

| Service      | URL                                  |
|--------------|--------------------------------------|
| Grafana      | <http://grafana.doghouse.lan>        |
| Prometheus   | <http://prometheus.doghouse.lan>     |
| Alertmanager | <http://alertmanager.doghouse.lan>   |

Grafana login user is `admin`; the password is a random value in the SOPS-encrypted `grafana-admin` Secret (wired via `grafana.admin.existingSecret`). Read it with:
```sh
SOPS_AGE_KEY_FILE=age.agekey sops -d \
  infrastructure/controllers/kube-prometheus-stack/grafana-admin.sops.yaml
```

DNS prerequisite: add a host override (or wildcard `*.doghouse.lan`) in OPNsense Unbound resolving to `10.1.1.250`. This lives in the Ansible repo, not here.

For Proxmox-specific dashboards, import Grafana dashboard ID **10347** ("Proxmox via Prometheus") once the stack is up.

## Headlamp (cluster UI)

[Headlamp](https://headlamp.dev) is the web UI for poking at the cluster itself, served via the same Traefik ingress:

| Service  | URL                              |
|----------|----------------------------------|
| Headlamp | <http://headlamp.doghouse.lan>   |

Add the `headlamp.doghouse.lan` host override (or rely on the `*.doghouse.lan` wildcard) in OPNsense Unbound, same as the monitoring UIs.

Login uses a bearer token. A `headlamp-admin` ServiceAccount bound to `cluster-admin` and a non-expiring token Secret are created by Flux. The token is minted server-side and never stored in git — fetch it and paste it into Headlamp's token prompt:

```sh
kubectl -n headlamp get secret headlamp-admin-token \
  -o jsonpath='{.data.token}' | base64 -d; echo
```

`cluster-admin` is full read/write over the whole cluster — fine for a single-admin homelab, but scope it down with a narrower ClusterRole if that ever changes.

## Verification

```sh
flux get kustomizations -A
flux get helmreleases -A
kubectl -n monitoring get pods
kubectl -n monitoring logs deploy/prometheus-pve-exporter
```

Prometheus targets page (<http://prometheus.doghouse.lan/targets>) should show these jobs UP:
- `prometheus-pve-exporter` — PVE API metrics.
- `node-exporter` — bare-metal host metrics (CPU temp, fan, etc.) for every host, provisioned by Ansible. The chart's bundled node-exporter DaemonSet is disabled (would collide with the systemd unit on :9100) and this static scrape job takes the slot, so the chart's bundled `defaultRules.rules.node` alerts fire against these targets.

Quick PromQL smoke tests: `pve_up`, `node_hwmon_temp_celsius{layer="bare-metal"}`, `node_cpu_seconds_total`.

## CPU temperatures

Bare-metal `node-exporter` is installed on each host out-of-band (Ansible). Prometheus scrapes those exporters directly via `additionalScrapeConfigs` in the `kube-prometheus-stack` HelmRelease — see the `node-exporter` job. The metric to alert on for overheating is `node_hwmon_temp_celsius` (filterable by `{layer="bare-metal"}`).
