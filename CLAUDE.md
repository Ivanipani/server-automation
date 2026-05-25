# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Declarative homelab automation for **poochella**: a small Proxmox VE fleet running a k3s Kubernetes cluster on node-local LVM-thin-backed VMs, fronted by an OPNsense router. OpenTofu provisions infrastructure on Proxmox; Ansible configures everything else. The control node is the user's laptop.

**Physical hosts split by role, not by hardware.** Today: `pve-home-01` is the only Proxmox hypervisor (mini PC); `worker-home-02` (renamed from `pve-home-02`) is plain Debian 13 baremetal (gaming-PC hardware that replaced the old crash-looping unit, since de-Proxmoxed for use as a Linux worker — both VM-host and baremetal kube_worker). `pve-home-03` was retired. Inventory umbrella groups: `physical` = every baremetal Linux box (`hypervisors` ∪ `workers`); `hypervisors` is PVE-only; `workers` is plain Linux.

**Proxmox topology is per-group, and clustered + standalone can coexist** (see `inventory.yaml` header). Today every hypervisor sits in `pve_standalone` — **no corosync, no shared storage, no HA, no live-migration**. The corosync path is still fully wired and supported for any node placed under a `pve_cluster` child group; it is simply a no-op while every node is standalone.

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

**Infra layout (tier directories).** `playbooks/poochella/infra/` is **six** ordered tiers, each a directory with its own ordered `site.yml`; ordinals are gap-10 *within* a tier so steps insert without renumbering. The directory **is** the target tier:
- `10-router/` — OPNsense DNS/DHCP foundation (precedes everything)
- `15-nas/` — Synology NAS (gap-5 break; independent of host bootstrap, admin'd via DSM rather than the ansible-user path)
- `17-host/` — Baseline for every baremetal Linux host (`physical` = hypervisors + workers): `10-bootstrap (ansible/pani/tourmanager users) → 15-storage (DESTRUCTIVE LVM-thin carve from inventory storage.disks; no-op on hosts without a storage block) → 16-nfs-mounts (NFS shares declared in physical_nfs_mounts; default empty for workers, hypervisors override to add proxmox RW) → 20-ssh-hardening → 30-firewall → 40-tailscale → 50-node-exporter`. The read-only companion `15-storage-plan.yml` is driven by `just disk-plan`.
- `20-hypervisor/` — Proxmox-only fabric (PVE-specific follow-up after 17-host built the LVM substrate): `10-bootstrap (repo flip) → 20-cluster (no-op standalone) → 30-pve-storage-register (publishes the LVM-thin pools from 17-host as PVE lvmthin storages under the frozen-contract names vms + longhorn-data) → 40-templates (per-node virt-customize + qm template bake)`. Targets `hypervisors`. The alternate `40-bake-images.yml` (Packer → NAS publish path) is not imported by default; flip the `site.yml` import to switch between local-bake and NAS-publish flows.
- `30-guests/` — OpenTofu barrier (`10-opentofu.yml` + `15-bootserv.yml`); the single point where the router + hypervisor tracks converge and guests come into existence
- `40-kube/` — guest config: `10-longhorn-host-prep → 20-k3s`

Each playbook self-bootstraps (`../tasks/detect-bootstrap-user.yml`) and asserts its own pre-conditions, so the ordering is the happy path, not the only path — any single tier playbook is runnable in isolation for piecemeal dev (`just run --limit <host>` then fzf-pick it).

**Bootstrap ordering** (the recipes that exist as `just`-shortcuts; the full chain is `just run` + `site.yml`):
1. `just do-router-dhcp` — push dnsmasq static DHCP+DNS leases onto OPNsense for every physical-host MAC
2. `just do-host-init` — apply the full 17-host tier to every `physical` host: users (ansible / pani / tourmanager), SSH hardening, firewall, tailscale, node-exporter
3. `just do-bootserv-config` — re-render bootserv01's iPXE + preseed templates (fast iteration during the netboot trial)
4. `just disk-plan` — read-only: dump every physical host's disks (hypervisors + workers) + paste-ready `storage.disks` skeleton. Run after any disk add/swap

The PVE tier (`20-hypervisor/` — cluster join, PVE storage registration, template bake) and 30-guests / 40-kube don't have dedicated `just-do-X` recipes; run them via `just run` (fzf-picks a playbook) or by invoking the tier's `site.yml` directly. The DESTRUCTIVE LVM carve itself lives in `17-host/15-storage.yml` (`just do-host-init` covers it as part of the full 17-host tier).

Full end-to-end is `playbooks/poochella/site.yml` (imports `infra/site.yml`); `infra/site.yml` imports the six tier `site.yml`s in order, and each tier `site.yml` imports its playbooks in ordinal order.

### Vault

- Indirection layer: roles/playbooks reference unprefixed names (`proxmox_api_token`, `k3s_cluster_token`, …) defined in `group_vars/all/vars.yml`, which re-export `vault_*` values from the encrypted `group_vars/all/vault.yml`. When adding a new secret, edit both files.
- **Per-hypervisor Proxmox tokens**: independent nodes don't share `/etc/pve`, so each PVE host has its own `tofu-lan` API token. `group_vars/all/vars.yml` exposes a `proxmox_api_tokens` map keyed by hypervisor name (workers don't run the PVE API and don't appear here). Add a hypervisor = mint with `pveum user token add root@pam tofu-lan --privsep 0` on that node, then `just secret-encrypt vault_proxmox_api_token_<host>`. See the header of `30-guests/10-opentofu.yml`.
- **Break-glass account**: the `tourmanager` user is the ONLY account that can SSH with a password after `17-host/20-ssh-hardening.yml` runs (a `Match User tourmanager` block in the sshd drop-in keeps password auth for it alone). The password lives in `vault_tourmanager_user_pass`.

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
- `physical` → umbrella for **every** baremetal Linux box (the 17-host tier targets this). Children:
  - `hypervisors` → PVE hosts only (the 20-hypervisor tier targets this). Children:
    - `pve_standalone` → independent nodes, **no corosync** (currently `pve-home-01` only)
    - `pve_cluster` → parent of zero or more corosync clusters. Each **child** group is one cluster: the group name *is* the cluster name, and `group_vars/<name>.yml` sets `proxmox_cluster_name: <name>`. Empty today.
  - `workers` → plain Linux baremetal (no PVE). k3s baremetal workers, app hosts, etc. Currently: `worker-home-02` (also listed in `kube_workers`). Workers do NOT appear in `proxmox_endpoints` / `template_*_ids` and Tofu does not see them.
- `switches` → managed network gear that wants a static lease
- `virtual-machines` → has children `databases` and `kubernetes`
- `kubernetes` → children `kube_control_plane` (kube-ctl-01..03) and `kube_workers` (kube-worker-01; -02/-03 commented out). All VM-based kube nodes are pinned to `pve-home-01` while it is the only hypervisor.
- `containers` → `bootserv` (bootserv01 LXC on pve-home-01) + `webservers` placeholder

`all.vars.proxmox_endpoints` is a `{hypervisor → https://…:8006}` map (one API endpoint per PVE host). Adding a hypervisor touches four places — see the checklist in `tofu/provider.tf`.

### Provisioning flow

VMs are declared once in `inventory.yaml` (any host with a `vm:` block). `tofu/locals.tf` walks the inventory, shapes those entries, and **partitions them by `proxmox_node`** into `vms_by_node`. The MAC declared in inventory is set on the VM NIC, so the static DHCP reservation pushed to OPNsense in step 1 of the bootstrap (`just do-router-dhcp`) lights up the moment the VM DHCPs — VMs come up on their reserved IP rather than whatever the pool hands out.

**Provider-per-hypervisor**: independent hypervisors don't share an API (hypervisor-A's endpoint can't create a VM on hypervisor-B), so `tofu/provider.tf` declares **one aliased `proxmox` provider per hypervisor**, and `tofu/main.tf` instantiates the reusable `tofu/modules/vm` module **once per hypervisor**, wiring each to its alias and its `vms_by_node` slice. Terraform can't generate provider blocks from data, so they are static — adding a hypervisor is the 4-step checklist in `tofu/provider.tf` (endpoint, token var, provider block, module call). This structure also works for cluster members, so one shape serves both topologies.

`playbooks/poochella/infra/30-guests/10-opentofu.yml`:
1. For **every** hypervisor, asserts a token exists for it in the vault (`proxmox_api_tokens[node]`) **and** that `tofu-lan` exists on that node via its own `pveum user token list`
2. Runs `community.general.terraform` against `tofu/` from `localhost`, passing each node's token via a per-node `TF_VAR_proxmox_api_token_<node>` env var (never written to disk in plaintext)

VM disks live on the **node-local** `vms` LVM-thin storage (same storage ID on every hypervisor, each backed by that node's own VG). Every hypervisor bakes its **own** templates: `20-hypervisor/40-templates.yml` runs on all of `hypervisors` and each node downloads, customizes, syspreps and templatizes locally (the old bake-once + `qm migrate` path needed a cluster and is removed; `tasks/distribute-templates-to-node.yml` is now dormant). Cloud image URLs are **pinned to dated upstream snapshots** so per-node bakes are deterministic — re-pin by bumping `image_url` + `image_file` together. Each node's template VMID comes from the explicit `template_vm_ids` / `template_ct_ids` maps in `inventory.yaml` (single source of truth, also read by `tofu/locals.tf`). Each VM is created on and pinned to its `proxmox_node` and cloned from that node's local template. The bpg/proxmox v0.106 `initialization` block has no `hostname` field — VM `name` propagates to cloud-init instead. DNS + search domain reach guests via DHCP options set on OPNsense (single source of truth for DNS).

### Storage carving (DESTRUCTIVE)

**Declared, not discovered — but by stable selector, not device name.** Each physical host's disk layout is the `storage.disks` list in `inventory.yaml` (single source of truth; the schema is the SAME for hypervisors and workers — the role distinguishes them by which fields each partition declares). Each disk has a `select:` (`boot` | `{model,serial}` | `{min_size_gib|size_gib, rotational}`), an optional per-disk `wipe: refuse|force`, and an ordered `partitions:` list. A non-`boot` selector **must resolve to exactly one** non-boot, non-removable disk — 0 or >1 matches is a **hard preflight failure** (the role never guesses, never auto-claims). Selectors match hardware attributes, so kernel renames (`sdX`/`nvmeXnY` shuffle on disk add) are irrelevant and swapping a disk for an identical/larger one needs **no inventory edit** when the selector is attribute-based. `just disk-plan` (read-only `17-host/15-storage-plan.yml`) prints every physical host's disks + a paste-ready skeleton (the skeleton form switches per group: PVE-style for hypervisors, mount-style for workers).

Each partition declares `label` (GPT partlabel + idempotency key, **unique per node**), `vg`, `thinpool`, `size` (sgdisk `+SIZE`; `0` = fill), then **EXACTLY ONE** of (XOR, enforced in preflight): `pve_storage` (a **frozen contract**: `tofu/modules/vm` hardcodes `vms`/`longhorn-data`; Tofu does *not* read `storage:` so the schema is Ansible-only) + `content`, OR `mount: { path, fstype, lv_name?, lv_size? }` (the role builds a thin LV, ext4s it, and fstab-mounts it). Several partitions on **different physical disks** may share one `vg`/`thinpool` — that is how a NVMe + HDD present as one larger pool (`longhorn-data` on a hypervisor, `longhornthin` mounted at `/var/lib/longhorn` on a worker; on the worker the `mount:` block lives on exactly ONE partition per pool). The hypervisor-only convention (asserted in preflight, see `group_vars/hypervisors.yml`): every hypervisor yields `vms` (universal — every VM/LXC boot disk uses it); a hypervisor that hosts a VM with `vm.data_disk_size` ALSO yields `longhorn-data`. CP-only hypervisors don't need `longhorn-data`: pve-home-01 today carries the k3s CPs + bootserv01 only and is sized to a single 256 GB NVMe (vms only); a future longhorn-hosting hypervisor wants ≥1 TB and extra disks extend `longhorn-data`.

`17-host/15-storage.yml` (`preflight.yml` → `_resolve_disk.yml` → `carve.yml` → `_wipe_disk.yml` + `_carve_one.yml` → `storage_pools.yml`): preflight resolves every selector to exactly one device and asserts the partlabel-uniqueness and pool-target-consistency invariants. Hypervisor-only preflight steps (gated by `when: inventory_hostname in groups['hypervisors']`): the `qm/pct list` + template detection guards, the `pve` VG assertion, the frozen-contract assertion, and the **non-fatal** advisory that a pinned worker's `data_disk_size` fits the longhorn pool. The template-classification gate: any **real (non-template)** VM/container is a hard refusal; **regenerable templates** only block unless `carve_destroy_templates: true`, in which case preflight `qm/pct destroy --purge`es them first (40-templates.yml re-bakes them next tier). Carve runs a per-disk **wipe gate** once per disk (boot disk never wiped; a disk already carrying our partlabels is skipped — idempotent; a disk with **foreign signatures** is REFUSED unless it declares `wipe: force`), then carves each partition in declared order (idempotent on the GPT partlabel). `storage_pools.yml` builds the `vg`/`thinpool` LVM-thin pool (a VG may span multiple PVs), **grows** an existing thin pool onto a newly-fitted larger disk (`lvextend +100%FREE`), and — for any partition with `mount:` — creates the thin LV, ext4-formats it, and persists the mount in fstab. The PVE-side publish step is decoupled: `20-hypervisor/30-pve-storage-register.yml` runs `pvesm add lvmthin` for each unique `pve_storage`, scoped `--nodes <self>` (independent nodes ⇒ per-node `/etc/pve/storage.cfg`). Disk swap / capacity / NAS-backup runbook: `docs/storage-disk-runbook.md`. **Data safety is a Longhorn-layer property (separate Flux repo), not an LVM one** — the carve only makes the empty re-init safe; Longhorn's replica-2 + zone anti-affinity is what survives a disk pull.

Longhorn placement: VM-based `kube_workers` declare `vm.data_disk_size`, get a `longhorn-data`-backed second disk on their hypervisor, and `40-kube/10-longhorn-host-prep.yml` ext4-mounts `/dev/vdb` at `/var/lib/longhorn`. Baremetal `kube_workers` (e.g. `worker-home-02`) declare `storage.disks` with a `mount: /var/lib/longhorn ext4` partition that `host-disks` realises directly; the VM-only `/dev/vdb` play in `10-longhorn-host-prep.yml` short-circuits cleanly. Either way, the future Longhorn install must restrict storage scheduling to the workers (`createDefaultDiskLabeledNodes` + label only workers) so replica-rebuild IO never lands on the etcd nodes.

### k3s + kube-vip

`playbooks/poochella/infra/40-kube/20-k3s.yml` builds an embedded-etcd HA cluster (k3s runs inside VM-based control planes, plus an agent on the baremetal `worker-home-02`; CP VMs are all pinned to `pve-home-01` while it is the only hypervisor, so that host is the etcd blast radius):
1. First CP runs `k3s server --cluster-init`; kube-vip is then deployed only on that node to bring up the L2 VIP at `k3s_kube_vip_address` (currently `10.1.1.50`)
2. Remaining CPs join `serial: 1` via `https://<api-endpoint>:6443` where api-endpoint is `k3s_api_dns_name` if set, else the VIP; workers join after
3. kubeconfig is fetched back to `{{ playbook_dir }}/../../../kubeconfig` (repo root) with its `server:` URL rewritten to the DNS name (else the VIP) — `export KUBECONFIG=$(pwd)/kubeconfig` to use it

The VIP must be a free address on the same L2 segment as the control planes. Config lives in `group_vars/kubernetes.yml`. Layered on top of the VIP is `k3s_api_dns_name: api.doghouse.lan` — pushed to OPNsense Unbound by `10-router/30-unbound.yml` (the more-specific override coexists with the `*.doghouse.lan` ingress wildcard). The k3s role uses the DNS name for the joiner `--server` URL, the rewritten kubeconfig `server:`, and as a TLS SAN on the apiserver cert; kube-vip still owns sub-second L2 failover between CPs, the DNS layer is sugar on top. Renumbering the VIP is therefore a one-line DNS edit. The bootstrap order (10-router before 40-kube) already satisfies the soft DNS dependency the layer introduces.

### Roles

Roles under `roles/` are units of work, not "things to install":
- `host-base` — every physical-host baseline: install sudo+zsh, import `apt-no-auto-upgrades`, create `ansible`/`pani`/`tourmanager` users via `create-user`, set root password from vault. Driven by `17-host/10-bootstrap.yml`. The user policy is in `defaults/main.yml`'s `host_base_users`.
- `ssh-hardening` — drops `/etc/ssh/sshd_config.d/10-hardening.conf` from a template: disables password+root login globally, but a `Match User <breakglass>` block keeps password auth for one specific user (defaults to `tourmanager`). Runs after `host-base` in the 17-host tier so the keys are enrolled before password auth turns off. Asserts the break-glass user exists; the drop-in is validated with `sshd -t` before it lands.
- `hypervisor` — PVE-only repo flip (enterprise → no-subscription PVE+Ceph). Its `cluster_ssh.yml` / `cluster_create.yml` / `cluster_join.yml` are **active but per-group**: scoped to `groups[proxmox_cluster_name]`, driven by `20-hypervisor/20-cluster.yml`, no-op when standalone (not dormant like ceph). Driven by `20-hypervisor/10-bootstrap.yml`. Generic baremetal setup that used to live inline here is now in `host-base`.
- `host-disks` — **declared, selector-based** (inventory `storage.disks`) disk carving + node-local LVM-thin pool provisioning for every physical host (hypervisors + workers). Each partition declares EITHER `pve_storage` + `content` (publisher = the PVE-only `20-hypervisor/30-pve-storage-register.yml`) OR `mount: { path, fstype, ... }` (role builds a thin LV, ext4s it, fstab-mounts it — used for `/var/lib/longhorn` on baremetal kube_workers). Tasks: `preflight.yml` → `_resolve_disk.yml`, `carve.yml` → `_wipe_disk.yml` + `_carve_one.yml`, `storage_pools.yml`; read-only `discover.yml` behind `just disk-plan`. Disks selected by `boot` / model+serial / size+rotational; multiple partitions/disks may back one (vg,thinpool). PVE-specific preflight (qm/pct list, `pve` VG assertion, frozen-contract assertion, longhorn capacity advisory) is gated on `inventory_hostname in groups['hypervisors']`.
- `ceph`, `ceph-csi` — **dormant** (Ceph removed): kept on disk for reference, not referenced by any active playbook/recipe
- `k3s` — task-file-per-phase (`server_init.yml`, `kube_vip.yml`, `server_join.yml`, `agent.yml`, `fetch_kubeconfig.yml`); playbooks `import_role` with `tasks_from:` rather than running the role as a whole
- `apt-no-auto-upgrades` — disable automatic ("unattended") apt upgrading: pins `APT::Periodic` to `"0"` + masks the apt-daily timers. Imported by `host-base` (every physical host) and `30-guests/30-disable-auto-upgrades.yml` (VMs); the kill-switch is also baked into the golden template by `20-hypervisor/40-templates.yml`. Patching is deliberate, not unattended — the `unattended-upgrades` package is left installed
- `firewall-basic` — ufw default-deny + per-group `inbound_allow` / `outbound_deny`. Driven from both `17-host/30-firewall.yml` (every physical host) and `30-guests/40-firewall.yml` (every guest). Each leaf group's policy lives in its `group_vars/<group>.yml`.
- `opnsense-dnsmasq` — DHCP static leases + DNS records on the router
- `create-user`, `ivan-user`, `dev-tools`, `python`, `golang`, `node`, `install-rust` — user/dev environment
- `caddy`, `nginx`, `postgres`, `pihole`, `docker`, `tailscale`, `node-exporter` — services

## Conventions

- Playbook filenames are prefixed `NN-` to encode run order within `infra/`. Don't reorder by renumbering unless you also understand the dependencies.
- The Ansible remote user is `ansible` with key `~/.ssh/ansible` (set in `ansible.cfg`). Cloud-init bakes this user into VM templates (`20-hypervisor/40-templates.yml`); the `host-base` role creates it on every physical host.
- Pre-conditions are documented as comment blocks at the top of each infra playbook — read those before editing.
- `playbooks/wip/` is scratchpad / in-progress work, not part of `site.yml`.

## Collaboration rules (for Claude)

- **Diagnose by running read-only ansible ad-hoc commands directly**, e.g. `ansible pve-home-01 -m shell -a 'pveam list local' --become`, `ansible bootserv01 -m shell -a 'systemctl is-active dnsmasq nginx' --become`. Do not ask the user to copy/paste terminal output when an ad-hoc command can fetch the same information. The `ansible` user + `~/.ssh/ansible` key already trusts every fleet host.
- **Never run a destructive command on the fleet without explicit per-command user permission.** "Destructive" = anything that mutates state on the host (`pct destroy`, `pveam remove`, `pvesm remove`, `rm`, `systemctl stop/disable`, `apt remove`, `qm destroy`, partitioning / disk wipes, killing processes, writing files outside `/tmp`, etc.). Reading config, listing resources, dumping logs, and `--check`/`--diff` dry-runs are fine. The same rule applies to OpenTofu (`tofu apply` against existing resources is destructive in principle) and to anything that touches OPNsense state.

## bootserv01 / iPXE boot flow

`bootserv01` is an LXC on `pve-home-01` (inventory `containers.bootserv.bootserv01`, `lxc:` block tagged `infra`) that serves TFTP (iPXE chainload binaries) and HTTP (boot scripts + Debian netboot kernel/initrd + per-host preseeds) to baremetal hosts that net-boot from their NIC. OPNsense's dnsmasq advertises `ipxe.efi` / `undionly.kpxe` to vanilla-PXE clients (chainload) and a script URL to user-class iPXE clients. Per-host iPXE dispatch + preseed are rendered by the `bootserv` Ansible role from inventory hosts that carry a `debian_netboot:` block.

**Tofu ordering invariant**: LXCs whose `lxc.tags` contains `infra` come up before any VMs. `tofu/main.tf` per-node `vms_<node>` modules declare `depends_on = [module.<node>_infra_lxcs]`, so a fresh `tofu apply` always brings bootserv01 up before kube/dev VMs that may reference it.
