# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Declarative homelab automation for the **poochella** cluster: a 3-node Proxmox VE cluster (`pve-home-01..03`) running an HA k3s Kubernetes cluster on node-local LVM-thin-backed VMs, fronted by an OPNsense router. OpenTofu provisions infrastructure on Proxmox; Ansible configures everything else. The control node is the user's laptop. (Ceph was removed in favour of node-local storage; the `ceph`/`ceph-csi` roles and `03b-install-ceph.yml`/`10-install-ceph-csi.yml` remain on disk as dormant reference but are no longer wired into any playbook or recipe.)

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

**Bootstrap ordering** (poochella infra is staged; recipes encode the dependencies):
1. `just do-router-dhcp` — push dnsmasq static leases onto OPNsense for baremetal MACs
2. `just do-hypervisor-init` — bootstrap PVE nodes, shell, users, dev tools
3. `just do-cluster-init` — form the PVE cluster (after all three nodes are reachable)
4. `just do-partition-disks` — **DESTRUCTIVE**, see warning below
5. `just do-provision-storage` — build node-local LVM-thin pools on the carved partitions and register them as PVE storage (`vms`, `longhorn-data`)

(After VM provisioning + k3s, `just do-longhorn-storage` formats/mounts the workers' second disk at `/var/lib/longhorn`.)

Full end-to-end is `playbooks/poochella/site.yml` (imports `infra/site.yml` then `trunk/site.yml`); the numbered playbooks under those directories are run in lexical order.

### Vault

- Indirection layer: roles/playbooks reference unprefixed names (`proxmox_api_token`, `k3s_cluster_token`, …) defined in `group_vars/all/vars.yml`, which re-export `vault_*` values from the encrypted `group_vars/all/vault.yml`. When adding a new secret, edit both files.

## Architecture

### Inventory (`inventory.yaml`)

Single source of truth for every host in the homelab. Read by Ansible (as its inventory; see `ansible.cfg`), by OpenTofu via `yamldecode` (`tofu/locals.tf`), and by the dnsmasq playbook (which walks hostvars to build static reservations).

Per-host fields:
- `ansible_host` — DNS name or IP Ansible uses to reach the host
- `ip_address` + `mac_address` — host appears as a dnsmasq static DHCP+DNS reservation on OPNsense
- `static_ip: true` — suppress the dnsmasq reservation (e.g. the router itself)
- `vm: { proxmox_node, cores, memory, disk_size, tags, ... }` — Tofu creates this VM on Proxmox, pinned to `proxmox_node`. VM MACs use the locally-administered `02:` prefix. Optional `vm.data_disk_size` (GiB) attaches a second virtio disk on the node-local `longhorn-data` storage (k3s workers, for Longhorn).

Groups define topology:
- `router` → OPNsense (`opnsense01` at `10.1.1.1`)
- `baremetal` → the three PVE hosts (`pve-home-01..03.lan`)
- `switches` → managed network gear that wants a static lease
- `virtual-machines` → has children `databases` and `kubernetes`
- `kubernetes` → children `kube_control_plane` (kube-ctl-01..03) and `kube_workers` (kube-worker-01..03)
- `containers` → currently only `webservers` as a child (template for future LXCs)

### Provisioning flow

VMs are declared once in `inventory.yaml` (any host with a `vm:` block). `tofu/locals.tf` walks the inventory and shapes those entries into the `vms` map consumed by `proxmox_virtual_environment_vm`. The MAC declared in inventory is set on the VM NIC, so the static DHCP reservation pushed to OPNsense in step 1 of the bootstrap (`just do-router-dhcp`) lights up the moment the VM DHCPs — VMs come up on their reserved IP rather than whatever the pool hands out.

LXCs still live in `tofu/infrastructure.auto.tfvars` (`containers = { … }`). Playbook `playbooks/poochella/infra/05-provision-infrastructure.yml`:
1. Asserts `vault_proxmox_api_token` is present locally **and** that the matching token exists on `pve-home-01` via `pveum user token list`
2. Runs `community.general.terraform` against `tofu/` from `localhost`, passing the API token via `TF_VAR_proxmox_api_token` (never written to disk in plaintext)

VM disks live on the **node-local** `vms` LVM-thin storage (same storage ID on every node, each backed by that node's own VG). There is **no shared storage, no live-migration, no HA**: storage being node-local, every node builds its own template with a per-node-unique ID (`base + node_index * template_vm_id_node_stride`, computed identically in `tofu/locals.tf` and `04-prepare-templates.yml`), and each VM is created on and pinned to its `proxmox_node` and cloned from that node's template. The bpg/proxmox v0.106 `initialization` block has no `hostname` field — VM `name` propagates to cloud-init instead. DNS + search domain reach guests via DHCP options set on OPNsense (single source of truth for DNS).

### Storage carving (DESTRUCTIVE)

`playbooks/poochella/infra/03-partition-disks.yml` carves the unallocated tail of each PVE boot disk into two GPT partitions: `vm-storage` (~`hypervisor_disks_vm_storage_percent`% of the tail, default 45%) and `longhorn` (fills the rest). `roles/hypervisor-disks/tasks/compute_layout.yml` computes the `vm-storage` size at runtime from the live free tail (`sgdisk -F`/`-E`); the carve is idempotent on the GPT partition label. Gated by `confirm_carve_data_disk: true` in `group_vars/baremetal.yml` and **requires PVE installed with `lvm.hdsize = 100`** (~900 GB unallocated); the answer files under `scripts/images/proxmox/pve-home-0X.toml` set this. `03b-provision-storage.yml` then builds a node-local LVM-thin pool on each partition (`vmdata/vmthin`, `longhorndata/longhornthin`) and registers them as the cluster-wide PVE storages `vms` (content `images,rootdir`) and `longhorn-data` (content `images`).

Longhorn (future) is **workers-only by design**: only `kube_workers` declare `vm.data_disk_size`, so only they get a `longhorn-data`-backed second disk (`09b-longhorn-storage.yml` ext4-mounts it at `/var/lib/longhorn`). k3s control planes here are schedulable (no `--node-taint`) and may run stateless pods, but the future Longhorn install must restrict storage scheduling to the workers (`createDefaultDiskLabeledNodes` + label only workers) so replica-rebuild IO never lands on the etcd nodes.

### k3s + kube-vip

`playbooks/poochella/infra/09-install-kubernetes.yml` builds an embedded-etcd HA cluster:
1. First CP runs `k3s server --cluster-init`; kube-vip is then deployed only on that node to bring up the L2 VIP at `k3s_kube_vip_address` (currently `10.1.1.50`)
2. Remaining CPs join `serial: 1` via `https://<VIP>:6443`; workers join after
3. kubeconfig is fetched back to `{{ playbook_dir }}/../../../kubeconfig` (repo root) with its `server:` URL rewritten to the VIP — `export KUBECONFIG=$(pwd)/kubeconfig` to use it

The VIP must be a free address on the same L2 segment as the control planes. Config lives in `group_vars/kubernetes.yml`. The role still supports an optional `k3s_api_dns_name` (DNS sugar in front of the VIP) but poochella doesn't set it — joiners and external kubectl hit the VIP IP directly, removing the runtime dependency on OPNsense DNS.

### Roles

Roles under `roles/` are units of work, not "things to install":
- `hypervisor`, `hypervisor-disks` — PVE node setup; disk carving + node-local LVM-thin pool/PVE-storage provisioning (`preflight.yml`, `compute_layout.yml`, `carve.yml`, `storage_pools.yml`)
- `ceph`, `ceph-csi` — **dormant** (Ceph removed): kept on disk for reference, not referenced by any active playbook/recipe
- `k3s` — task-file-per-phase (`server_init.yml`, `kube_vip.yml`, `server_join.yml`, `agent.yml`, `fetch_kubeconfig.yml`); playbooks `import_role` with `tasks_from:` rather than running the role as a whole
- `opnsense-dnsmasq` — DHCP static leases + DNS records on the router
- `create-user`, `ivan-user`, `dev-tools`, `python`, `golang`, `node`, `install-rust` — user/dev environment
- `caddy`, `nginx`, `postgres`, `pihole`, `docker`, `tailscale`, `firewall-basic` — services

## Conventions

- Playbook filenames are prefixed `NN-` to encode run order within `infra/` and `trunk/`. Don't reorder by renumbering unless you also understand the dependencies.
- The Ansible remote user is `ansible` with key `~/.ssh/ansible` (set in `ansible.cfg`). Cloud-init bakes this user into VM templates (`04-prepare-templates.yml`).
- Pre-conditions are documented as comment blocks at the top of each infra playbook — read those before editing.
- `playbooks/wip/` is scratchpad / in-progress work, not part of `site.yml`.
