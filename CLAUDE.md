# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Declarative homelab automation for **poochella**: a small Proxmox VE fleet running a k3s Kubernetes cluster on node-local LVM-thin-backed VMs, fronted by an OPNsense router. OpenTofu provisions infrastructure on Proxmox; Ansible configures everything else. The control node is the user's laptop.

**Proxmox topology is per-group, and clustered + standalone can coexist** (see the `inventory.yaml` header). Today poochella runs **two independent, non-clustered nodes** — `pve-home-01` (original hardware) and `pve-home-02` (new gaming-PC hardware that replaced the old crash-looping unit); `pve-home-03` was retired. There is **no corosync, no shared storage, no HA, no live-migration**. The corosync path is still fully wired and supported for any node placed under a `pve_cluster` child group; it is simply a no-op while every node is standalone.

(Ceph was removed in favour of node-local storage; the `ceph`/`ceph-csi` roles remain on disk as dormant reference, and the old ceph playbooks were lifted out of `infra/` into `playbooks/wip/`. Nothing wires ceph into any playbook or recipe.)

## Common commands

All workflows are wrapped in `justfile` recipes — prefer `just <recipe>` over invoking `ansible-playbook` directly:

- `just check` — verify control-node deps (ansible, fzf, collections, `passlib`)
- `just install` — install ansible-core via `uv tool install` plus required collections
- `just ping` — `ansible all -m ping` smoke test
- `just run [options]` — fzf-pick a playbook under `playbooks/` and run it (auto-passes `--vault-password-file ansible-pass`)
- `just test` — fzf-pick tags from `test/test.yml` and run that subset
- `just ssh-refresh` — clear & re-seed `known_hosts` for every host in the inventory (useful after re-imaging)
- `just secret-encrypt <name>` — `ansible-vault encrypt_string` for adding values to `group_vars/all/vault.yml`
- `just tofu-{validate,init,plan,apply}` — OpenTofu wrappers (operate from `tofu/`)

**Infra layout (tier directories).** `playbooks/poochella/infra/` is four ordered tiers, each a directory with its own ordered `site.yml`; ordinals are gap-10 *within* a tier so steps insert without renumbering. The directory **is** the target tier:
- `10-router/` — OPNsense DNS/DHCP foundation (precedes everything)
- `20-hypervisor/` — Proxmox baremetal fabric, the critical path: `10-bootstrap → 20-cluster (no-op standalone) → 30-storage (DESTRUCTIVE carve + LVM-thin + PVE register, merged) → 40-templates`; `50-tailscale`/`60-node-exporter` are order-independent day-2 services
- `30-provision/` — the OpenTofu barrier (`10-opentofu.yml`); the single point where the router + hypervisor tracks converge and guests come into existence
- `40-guests/` — guest config: `10-bootstrap (ansible user) → 20-disable-auto-upgrades → 30-firewall (opens k3s ports) → 40-longhorn-host-prep → 50-k3s`

Each playbook self-bootstraps (`../tasks/detect-bootstrap-user.yml`) and asserts its own pre-conditions, so the ordering is the happy path, not the only path — any single tier playbook is runnable in isolation for piecemeal dev (`just run --limit <host>` then fzf-pick it).

**Bootstrap ordering** (recipes encode the dependencies):
1. `just do-router-dhcp` — push dnsmasq static leases onto OPNsense for baremetal MACs
2. `just do-hypervisor-init` — bootstrap PVE nodes (+tailscale), shell, users, dev tools
3. `just do-cluster-init` — form corosync clusters **per group**. Scoped to hosts under `pve_cluster` child groups; a **no-op when every node is standalone** (poochella's current state). Kept in the bootstrap so adding a cluster group is the only change needed.
4. `just do-storage` — **DESTRUCTIVE** carve, then LVM-thin pools + PVE storage registration (`vms`, `longhorn-data`) — one merged playbook (`20-hypervisor/30-storage.yml`), see warning below

(After VM provisioning + k3s, `just do-longhorn-storage` formats/mounts the workers' second disk at `/var/lib/longhorn`.)

Full end-to-end is `playbooks/poochella/site.yml` (imports `infra/site.yml` then `trunk/site.yml`); `infra/site.yml` imports the four tier `site.yml`s in order, and each tier `site.yml` imports its playbooks in ordinal order.

### Vault

- Indirection layer: roles/playbooks reference unprefixed names (`proxmox_api_token`, `k3s_cluster_token`, …) defined in `group_vars/all/vars.yml`, which re-export `vault_*` values from the encrypted `group_vars/all/vault.yml`. When adding a new secret, edit both files.
- **Per-node Proxmox tokens**: independent nodes don't share `/etc/pve`, so each has its own `tofu-lan` API token. `group_vars/all/vars.yml` exposes a `proxmox_api_tokens` map keyed by node name; `pve-home-01` reuses the legacy `vault_proxmox_api_token`, every other node needs `vault_proxmox_api_token_<node>` added to the vault (mint with `pveum user token add root@pam tofu-lan --privsep 0` on that node, then `just secret-encrypt`). See the header of `05-provision-infrastructure.yml`.

## Architecture

### Inventory (`inventory.yaml`)

Single source of truth for every host in the homelab. Read by Ansible (as its inventory; see `ansible.cfg`), by OpenTofu via `yamldecode` (`tofu/locals.tf`), and by the dnsmasq playbook (which walks hostvars to build static reservations).

Per-host fields:
- `ansible_host` — DNS name or IP Ansible uses to reach the host
- `ip_address` + `mac_address` — host appears as a dnsmasq static DHCP+DNS reservation on OPNsense
- `static_ip: true` — suppress the dnsmasq reservation (e.g. the router itself)
- `vm: { proxmox_node, cores, memory, disk_size, tags, ... }` — Tofu creates this VM on Proxmox, pinned to `proxmox_node`. VM MACs use the locally-administered `02:` prefix. Optional `vm.data_disk_size` (GiB) attaches a second virtio disk on the node-local `longhorn-data` storage (k3s workers, for Longhorn); each worker is sized to consume its node's whole longhorn pool, kept just under the physical pool since it is thin-provisioned.

Groups define topology:
- `router` → OPNsense (`opnsense01` at `10.1.1.1`)
- `baremetal` → umbrella for **all** PVE hosts (shared roles target this; children flatten into it). Topology is decided by which child group a host sits in:
  - `pve_standalone` → independent nodes, **no corosync** (currently `pve-home-01`, `pve-home-02`)
  - `pve_cluster` → parent of zero or more corosync clusters. Each **child** group is one cluster: the group name *is* the cluster name, and `group_vars/<name>.yml` sets `proxmox_cluster_name: <name>`. Empty today.
- `switches` → managed network gear that wants a static lease
- `virtual-machines` → has children `databases` and `kubernetes`
- `kubernetes` → children `kube_control_plane` (kube-ctl-01..03) and `kube_workers` (kube-worker-01; -02/-03 commented out). All VMs are currently pinned to `pve-home-02`.
- `containers` → currently only `webservers` as a child (template for future LXCs)

`all.vars.proxmox_endpoints` is a `{node → https://…:8006}` map (one API endpoint per node). Adding a node touches four places — see the checklist in `tofu/provider.tf`.

### Provisioning flow

VMs are declared once in `inventory.yaml` (any host with a `vm:` block). `tofu/locals.tf` walks the inventory, shapes those entries, and **partitions them by `proxmox_node`** into `vms_by_node`. The MAC declared in inventory is set on the VM NIC, so the static DHCP reservation pushed to OPNsense in step 1 of the bootstrap (`just do-router-dhcp`) lights up the moment the VM DHCPs — VMs come up on their reserved IP rather than whatever the pool hands out.

**Provider-per-node**: independent nodes don't share an API (pve-home-01's endpoint can't create a VM on pve-home-02), so `tofu/provider.tf` declares **one aliased `proxmox` provider per node**, and `tofu/main.tf` instantiates the reusable `tofu/modules/vm` module **once per node**, wiring each to its alias and its `vms_by_node` slice. Terraform can't generate provider blocks from data, so they are static — adding a node is the 4-step checklist in `tofu/provider.tf` (endpoint, token var, provider block, module call). This structure also works for cluster members, so one shape serves both topologies.

`playbooks/poochella/infra/05-provision-infrastructure.yml`:
1. For **every** baremetal node, asserts a token exists for it in the vault (`proxmox_api_tokens[node]`) **and** that `tofu-lan` exists on that node via its own `pveum user token list`
2. Runs `community.general.terraform` against `tofu/` from `localhost`, passing each node's token via a per-node `TF_VAR_proxmox_api_token_<node>` env var (never written to disk in plaintext)

VM disks live on the **node-local** `vms` LVM-thin storage (same storage ID on every node, each backed by that node's own VG). Every node bakes its **own** templates: `04-prepare-templates.yml` runs on all of `baremetal` and each node downloads, customizes, syspreps and templatizes locally (the old bake-once + `qm migrate` path needed a cluster and is removed; `tasks/distribute-templates-to-node.yml` is now dormant). Cloud image URLs are **pinned to dated upstream snapshots** so per-node bakes are deterministic — re-pin by bumping `image_url` + `image_file` together. Each node's template VMID comes from the explicit `template_vm_ids` / `template_ct_ids` maps in `inventory.yaml` (single source of truth, also read by `tofu/locals.tf`). Each VM is created on and pinned to its `proxmox_node` and cloned from that node's local template. The bpg/proxmox v0.106 `initialization` block has no `hostname` field — VM `name` propagates to cloud-init instead. DNS + search domain reach guests via DHCP options set on OPNsense (single source of truth for DNS).

### Storage carving (DESTRUCTIVE)

**Declared, not discovered.** Each baremetal host's disk layout is the `storage.pools` list in `inventory.yaml` (single source of truth). The `hypervisor-disks` role only touches disks named there; an undeclared disk is never touched, and a declared disk that isn't physically present is a **hard preflight failure**. A hardware change (swap/add a drive) must be reflected in `inventory.yaml` *first*, then the playbook re-run — `just disk-ids` lists each node's `/dev/disk/by-id` paths to fill in.

Each pool declares stable, content-addressed identifiers — `pool` (GPT partlabel + idempotency key), `vg`, `thinpool`, `pve_storage` (a **frozen contract**: `tofu/modules/vm` hardcodes `vms`/`longhorn-data`), `content` — and a `backing` strategy:
- **`boot_tail`** — carve `size` (sgdisk `+SIZE`; `0` = fill the rest) at the end of the auto-detected PVE boot disk. Root/swap (first ~100 GiB) is already the `pve` VG from the installer's `lvm.hdsize = 100`. Used for `pve-home-01` (single ~1 TB disk) and `pve-home-02`'s SSD-tail `vm-storage`.
- **`whole_disk`** — claim the entire disk at `backing.by_id` (one full-disk GPT partition). Used for `pve-home-02`'s 1 TB HDD → `longhorn`.

`03-partition-disks.yml` (`preflight.yml` → `_resolve_pool.yml` → `carve.yml` → `_carve_one.yml`): preflight resolves every declared by-id, asserts it is present, is a whole disk, and is **not** the boot disk; the carve is idempotent on the GPT partlabel and refuses a `whole_disk` that holds **foreign signatures** (a blank replacement passes — `sgdisk` writes a fresh GPT — a disk with data fails until cleared). Gated by `confirm_carve_data_disk: true` in `group_vars/baremetal.yml`. `03b-provision-storage.yml` then builds the `vg`/`thinpool` LVM-thin pool per declared pool and registers each as PVE storage **on every node** (independent nodes ⇒ per-node `/etc/pve/storage.cfg`, scoped `--nodes <self>`). Swapping a disk → new serial → new by-id ⇒ inventory edit required; the blank replacement is re-initialised into the *same* pool because pool/vg/thinpool/storage-id are fixed by intent, not by the device.

Longhorn (future) is **workers-only by design**: only `kube_workers` declare `vm.data_disk_size`, so only they get a `longhorn-data`-backed second disk (`10-longhorn-storage.yml` ext4-mounts it at `/var/lib/longhorn`). k3s control planes here are schedulable (no `--node-taint`) and may run stateless pods, but the future Longhorn install must restrict storage scheduling to the workers (`createDefaultDiskLabeledNodes` + label only workers) so replica-rebuild IO never lands on the etcd nodes.

### k3s + kube-vip

`playbooks/poochella/infra/11-install-kubernetes.yml` builds an embedded-etcd HA cluster (k3s runs *inside the guest VMs*, independent of the Proxmox-layer topology — but note all CPs currently land on the single `pve-home-02`, so that host is the etcd blast radius):
1. First CP runs `k3s server --cluster-init`; kube-vip is then deployed only on that node to bring up the L2 VIP at `k3s_kube_vip_address` (currently `10.1.1.50`)
2. Remaining CPs join `serial: 1` via `https://<VIP>:6443`; workers join after
3. kubeconfig is fetched back to `{{ playbook_dir }}/../../../kubeconfig` (repo root) with its `server:` URL rewritten to the VIP — `export KUBECONFIG=$(pwd)/kubeconfig` to use it

The VIP must be a free address on the same L2 segment as the control planes. Config lives in `group_vars/kubernetes.yml`. The role still supports an optional `k3s_api_dns_name` (DNS sugar in front of the VIP) but poochella doesn't set it — joiners and external kubectl hit the VIP IP directly, removing the runtime dependency on OPNsense DNS.

### Roles

Roles under `roles/` are units of work, not "things to install":
- `hypervisor`, `hypervisor-disks` — PVE node setup; **declared** (inventory `storage.pools`, by-id) disk carving + node-local LVM-thin pool/PVE-storage provisioning (`preflight.yml` → `_resolve_pool.yml`, `carve.yml` → `_carve_one.yml`, `storage_pools.yml`); `boot_tail` + `whole_disk` backing strategies. `hypervisor`'s `cluster_ssh.yml` / `cluster_create.yml` / `cluster_join.yml` are **active but per-group**: scoped to `groups[proxmox_cluster_name]`, driven by `02b-cluster-hypervisor.yml`, no-op when standalone (not dormant like ceph)
- `ceph`, `ceph-csi` — **dormant** (Ceph removed): kept on disk for reference, not referenced by any active playbook/recipe
- `k3s` — task-file-per-phase (`server_init.yml`, `kube_vip.yml`, `server_join.yml`, `agent.yml`, `fetch_kubeconfig.yml`); playbooks `import_role` with `tasks_from:` rather than running the role as a whole
- `apt-no-auto-upgrades` — disable automatic ("unattended") apt upgrading: pins `APT::Periodic` to `"0"` + masks the apt-daily timers. Used by the `hypervisor` role (baremetal) and `06b-disable-auto-upgrades.yml` (VMs); the kill-switch is also baked into the golden template by `04-prepare-templates.yml`. Patching is deliberate, not unattended — the `unattended-upgrades` package is left installed
- `opnsense-dnsmasq` — DHCP static leases + DNS records on the router
- `create-user`, `ivan-user`, `dev-tools`, `python`, `golang`, `node`, `install-rust` — user/dev environment
- `caddy`, `nginx`, `postgres`, `pihole`, `docker`, `tailscale`, `firewall-basic` — services

## Conventions

- Playbook filenames are prefixed `NN-` to encode run order within `infra/` and `trunk/`. Don't reorder by renumbering unless you also understand the dependencies.
- The Ansible remote user is `ansible` with key `~/.ssh/ansible` (set in `ansible.cfg`). Cloud-init bakes this user into VM templates (`04-prepare-templates.yml`).
- Pre-conditions are documented as comment blocks at the top of each infra playbook — read those before editing.
- `playbooks/wip/` is scratchpad / in-progress work, not part of `site.yml`.
