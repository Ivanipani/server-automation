# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Declarative homelab automation for **poochella**: a small Proxmox VE fleet running a k3s Kubernetes cluster on node-local LVM-thin-backed VMs, fronted by an OPNsense router. OpenTofu provisions infrastructure on Proxmox; Ansible configures everything else. The control node is the user's laptop.

**Every Proxmox hypervisor is a fully standalone PVE host** — **no corosync, no shared storage, no HA, no live-migration**.

## Servers

3 x HP mini PCs. Each is a proxmox hypervisor running 1 k3s control-plane VM.

1. pve-home-01
2. pve-home-02
3. pve-home-03

2 x worker nodes. These are 12/24 core machines with NVMEs.

4. metal-home-01
5. metal-home-02

## Architecture

### Inventory (`inventory.yaml`)

Single source of truth for every host in the homelab. Read by Ansible (as its inventory; see `ansible.cfg`), by OpenTofu via `yamldecode` (`tofu/modules/hypervisor/locals.tf` + each `tofu/per-node/<host>/main.tf`), and by the dnsmasq playbook (which walks hostvars to build static reservations).

Per-host fields:
- `ansible_host` — DNS name or IP Ansible uses to reach the host
- `ip_address` + (`mac_addresses` for physical hosts | `mac_address` for VMs) — host appears as a dnsmasq static DHCP+DNS reservation on OPNsense. Physical hosts use a LIST of every NIC's MAC (multi-NIC hosts collapse to one OPNsense entry with all MACs in `hardware_addr`, and every entry is also a valid iPXE boot MAC). VMs have exactly one NIC and so a single `mac_address` string, which is also the MAC Tofu provisions on the VM NIC.
- `static_ip: true` — suppress the dnsmasq reservation (e.g. the router itself)
- `vm: { proxmox_node, cores, memory, disk_size, tags, ... }` — Tofu creates this VM on Proxmox, pinned to `proxmox_node`. VM MACs use the locally-administered `02:` prefix. VM boot disks live on the node-local `vms` PVE storage; no VM ever receives a Longhorn-backed data disk (replicas live only on baremetal kube_workers — see Storage carving below).

Groups define topology:
- `router` → OPNsense (`opnsense01` at `10.1.1.1`)
- `physical` → umbrella for **every** baremetal Linux box (the 17-host tier targets this). Children:
  - `hypervisors` → PVE hosts only (the 20-hypervisor tier targets this). Children:
    - `pve_standalone` → every PVE host lives here (today: `pve-home-01` only). No corosync, no shared storage.
    - `pve_cluster` → **gated off**: empty group kept as deprecated scaffolding only. `20-hypervisor/20-cluster.yml` asserts this group is empty and fails the play otherwise.
  - `workers` → plain Linux baremetal (no PVE). k3s baremetal workers, app hosts, etc. Currently: `worker-home-02` (also listed in `kube_workers`). Workers have no `vm:`/`lxc:` block and are not in the `hypervisors` group, so Tofu does not see them.
- `foundation` → top-level group containing the hypervisor(s) that must be all-the-way-up (full stack + bootserv01 LXC + bootserv role) before any other baremetal can come into being. Targeted by the 13-foundation tier via `target_hosts: foundation`. Today: just `pve-home-01`. Members MUST also appear under `hypervisors`.
- `switches` → managed network gear that wants a static lease
- `virtual-machines` → has children `databases` and `kubernetes`
- `kubernetes` → children `kube_control_plane` (kube-ctl-01..03) and `kube_workers` (kube-worker-01; -02/-03 commented out). All VM-based kube nodes are pinned to `pve-home-01` while it is the only hypervisor.
- `containers` → `bootserv` (bootserv01 LXC on pve-home-01) + `webservers` placeholder

### Flux / GitOps (`k8s/`) — public/private split

`k8s/` is the cluster's Flux GitOps root and is **PUBLIC, infrastructure-only**. It is the visibility boundary: the platform layer is committed here; **application manifests are private IP and never enter this repo's history** — they live in the separate private repo `github.com/Ivanipani/doghouse`, imported as an **opaque cross-repo source**.

- **Layout** (`k8s/clusters/doghouse/` is the Flux entrypoint): `flux-system/` (gotk-components + gotk-sync pointing at THIS repo, sync path `./k8s/clusters/doghouse`); `infra.yaml` (the infra Kustomizations); `apps.yaml` (the apps Kustomization + a dormant `doghouse-apps` GitRepository). Platform manifests are under `k8s/infra/{networking,storage,monitoring}/{controllers,configs}`. **Flux `spec.path` is repo-root-relative**, so every Kustomization path is prefixed `./k8s/…` — keep that prefix on any new one.
- **Apps import** (`apps.yaml`): today apps still live locally at `k8s/apps/doghouse` and the `apps` Kustomization sources `flux-system` (this repo), so the cluster works. The `doghouse-apps` GitRepository (→ private repo, authed by the read-only `doghouse-apps-key` Secret) is wired but dormant. **One-step cutover later**: move `k8s/apps` into the private repo, then flip the `apps` Kustomization's `sourceRef` `flux-system → doghouse-apps` and `path` `./k8s/apps/doghouse → ./apps/doghouse` (procedure documented at the top of `apps.yaml`).
- **Bootstrap is Ansible-driven**: `40-kube/40-flux.yml` (run via `just do-flux`, host `localhost`) runs `flux bootstrap git` against this repo over **SSH** (GitHub rejects PAT-over-HTTPS for git ops; key staged from `vault_github_ssh_private_key`, `--path=k8s/clusters/doghouse`) using the kubeconfig `20-k3s.yml` fetched, then installs the `sops-age` Secret from `vault_sops_age_key` and the `doghouse-apps-key` Secret from `vault_doghouse_apps_deploy_key` (each skipped if its vault value is unset/placeholder). Idempotent; it commits + pushes `flux-system/` to the repo.
- **SOPS**: encrypted `*.sops.yaml` are committed in the public repo (safe — only the age **public** key is exposed in `k8s/.sops.yaml`); the age **private** key is vaulted as `vault_sops_age_key` and never a loose tracked file (`*.agekey` is git-ignored). Decryption is wired via `spec.decryption` on the `storage-controllers` / `monitoring-controllers` Kustomizations.

### Ansible Guidelines

Plays/roles that install a service should have a boolean enable/disable flag capable of reversing or unapplying the change. Use blocks to group together each side.

## Collaboration rules (for Claude)

- **Use comments SPARSELY. Avoid over-explaining decisions.**
- **Diagnose by running read-only ansible ad-hoc commands directly**, e.g. `ansible pve-home-01 -m shell -a 'pveam list local' --become`, `ansible bootserv01 -m shell -a 'systemctl is-active dnsmasq nginx' --become`. Do not ask the user to copy/paste terminal output when an ad-hoc command can fetch the same information. The `ansible` user + `~/.ssh/ansible` key already trusts every fleet host.
- **Never run a destructive command on the fleet without explicit per-command user permission.** "Destructive" = anything that mutates state on the host (`pct destroy`, `pveam remove`, `pvesm remove`, `rm`, `systemctl stop/disable`, `apt remove`, `qm destroy`, partitioning / disk wipes, killing processes, writing files outside `/tmp`, etc.). Reading config, listing resources, dumping logs, and `--check`/`--diff` dry-runs are fine. The same rule applies to OpenTofu (`tofu apply` against existing resources is destructive in principle) and to anything that touches OPNsense state.
- **Use the NATO alphabet when naming cluster entities. Always start at Alpha and move up.**
- **Never use git commands to probe the commit history. Use jujutsu instead.**

