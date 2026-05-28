# Rebuild `worker-home-02` (baremetal Debian kube_worker)

## What this document covers

How to re-image the sole baremetal Debian worker `worker-home-02` and bring it back into the k3s cluster as a Longhorn data-bearing node. The runbook covers the destructive re-image (boot disk wipe + Debian unattended install via iPXE), the rejoin to the cluster, and verification.

Two recovery paths are documented:
- **Happy path**: only the boot SSD (`/dev/nvme0n1`) is wiped; the longhorn-data disks survive and Longhorn picks up its replicas automatically.
- **Pessimistic path**: the longhorn-data disks were also re-carved (or hardware was replaced); volumes must be restored from the NAS backup target.

This runbook does NOT cover:
- Hypervisor (`pve-home-01`) rebuilds.
- NAS (`nas01`) failure/replacement.
- Hot disk-swap on a live worker — that lives in `docs/storage-disk-runbook.md`.

## Topology assumptions

- One hypervisor: `pve-home-01`.
- One baremetal kube_worker: `worker-home-02` (10.1.1.106).
- `bootserv01` LXC runs on `pve-home-01` and serves iPXE + Debian preseed over TFTP/HTTP.
- NAS: `nas01` exports `/volume1/longhorn-backup` over NFS; Longhorn `BackupTarget` is wired to it (see `docs/runbooks/longhorn-backup.md`).
- Longhorn `defaultReplicaCount: 1` today. The NAS backup is the only durable copy of each volume's data.

## Pre-conditions (BLOCKING)

Do not proceed past any gate that fails.

1. **Backup target is healthy.** Must return `true`:
   ```bash
   kubectl get backuptarget -n longhorn-system default \
     -o jsonpath='{.status.available}'
   ```

2. **Every Longhorn volume on `worker-home-02` has a recent backup** (younger than 24h, or whatever the operator's RPO is):
   ```bash
   kubectl get volume -n longhorn-system -o json | jq '.items[]
     | select(.spec.nodeID == "worker-home-02")
     | {name: .metadata.name, lastBackupAt: .status.lastBackup}'
   ```
   If any `lastBackupAt` is empty or stale, BLOCK. Either wait for the RecurringJob to fire, or trigger a one-shot backup per volume from the Longhorn UI (Volume → Create Backup) and re-run this check.

3. **`bootserv01` is reachable and serving iPXE**:
   ```bash
   curl -sSf http://bootserv01.lan/boot.ipxe | head
   ```
   If this fails, the host will netboot into nothing. Run `just do-foundation` (brings up `pve-home-01` + `bootserv01` + the bootserv role) before proceeding.

4. **Operator has physical or IPMI access** to the box. There is no remote PXE-trigger automation; the host boots from the Mellanox ConnectX-4 Lx by BIOS first-boot order (see `boot_macs` in `ansible/inventory.yaml`).

5. **Drain has succeeded** — see step 2 of the procedure below.

## Procedure

### 1. Capture pre-state

Write down what the cluster looked like before, so the post-rebuild verification has a baseline to compare against.

```bash
kubectl get node worker-home-02 -o yaml > /tmp/worker-home-02.pre.yaml
kubectl get volume -n longhorn-system -o wide > /tmp/longhorn-volumes.pre.txt
kubectl get replica -n longhorn-system -o wide \
  | grep worker-home-02 > /tmp/longhorn-replicas.pre.txt
ansible worker-home-02 -b -m shell \
  -a 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,SERIAL' \
  > /tmp/worker-home-02.lsblk.pre.txt
```

### 2. Cordon, drain, and trigger a final backup

```bash
kubectl cordon worker-home-02
kubectl drain worker-home-02 --ignore-daemonsets --delete-emptydir-data
```

Daemonset pods (longhorn-manager, csi-plugin, node-exporter) intentionally stay scheduled.

Then trigger a one-shot Longhorn backup for every volume currently pinned to `worker-home-02` from the Longhorn UI (`https://longhorn.doghouse.lan` → Volume → Create Backup). Wait for each to reach `Completed` before continuing. Re-run the `lastBackupAt` check from pre-condition 2 to confirm.

### 3. Remove the node from the cluster

```bash
kubectl delete node worker-home-02
```

This drops the stale node object; the freshly imaged host will register a new one when k3s-agent starts. Longhorn-manager on the soon-to-be-imaged node will lose its CR shortly after.

### 4. Power-cycle into PXE

If the Mellanox NIC is still first in BIOS boot order (this is the standard config), a normal reboot is enough:

```bash
ansible worker-home-02 -b -m shell -a 'systemctl reboot'
```

If BIOS first-boot was changed, or the host is unreachable, use the box's physical keyboard / IPMI to force a network boot.

### 5. Watch the netboot + preseed

Tail bootserv01 to confirm the host pulls iPXE → kernel/initrd → preseed:

```bash
ansible bootserv01 -b -m shell \
  -a 'journalctl -u caddy -f --since "5 minutes ago"'
```

Expected request sequence (from the host's IP `10.1.1.106`):
- `GET /boot.ipxe`
- `GET /hosts/worker-home-02.ipxe`
- `GET /debian-13/{linux,initrd.gz}`
- `GET /preseed/worker-home-02.cfg`
- `GET /scripts/image-baseline.sh` (late_command)

The preseed's `early_command` walks `lsblk` and resolves the install target by matching the `hw: {model, serial}` block on the inventory's `storage.disks` entry marked `select: boot` — every other disk is untouched. The install finishes when the host responds on `worker-home-02.lan` again (a minute or two after the final iPXE/HTTP fetch).

Sanity-ping:
```bash
until ansible worker-home-02 -m ping >/dev/null 2>&1; do sleep 10; done
echo "worker-home-02 is back"
```

### 6. Refresh SSH known_hosts

The re-imaged host has new host keys. Without this step every subsequent `ansible` call against the host fails with `Host key verification failed`:

```bash
just ssh-refresh
```

### 7. Re-run the 17-host tier (users, ssh-hardening, firewall, tailscale, node-exporter)

```bash
just do-host-init
```

This is safe to run cluster-wide; idempotent on every other host. The recipe runs `playbooks/poochella/infra/17-host/site.yml`, which also includes `15-storage.yml` — i.e. the host-disks role gets applied here too. Since the role defaults to `host_disks_action: info`, the longhorn-data LVM is left alone if it already exists.

### 8. Verify the longhorn-data LVM survived

Read-only check:

```bash
just disk-plan
```

Look at the `worker-home-02` section of the output. Expected:
- `longhorndata` VG: **PRESENT**
- `longhornthin` thinpool: **PRESENT**
- `longhorn-data` LV mounted at `/var/lib/longhorn` (ext4): **PRESENT**

```bash
ansible worker-home-02 -b -m shell \
  -a 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; vgs longhorndata; mount | grep /var/lib/longhorn'
```

- If everything is PRESENT and mounted → continue with step 9 (happy path).
- If anything is MISSING → jump to **Recovery (pessimistic path)** below before doing step 9.

### 9. Rejoin the k3s cluster

Run the k3s playbook scoped to this host:

```bash
cd ansible
ansible-playbook --vault-password-file ansible-pass \
  --limit worker-home-02 \
  playbooks/poochella/infra/40-kube/20-k3s.yml
```

This installs the k3s-agent, sources the join token from the vault, and applies the worker labels: `topology.kubernetes.io/zone=<pve_node>` and `node.longhorn.io/create-default-disk=true` (see `ansible/group_vars/kube_workers.yml`).

## Verification (happy path)

```bash
# Node Ready
kubectl get nodes worker-home-02 -o wide

# Labels back in place
kubectl get node worker-home-02 \
  -o jsonpath='{.metadata.labels}' | jq | \
  grep -E 'longhorn|zone'
# Expect:
#   "node.longhorn.io/create-default-disk": "true"
#   "topology.kubernetes.io/zone": "pve-home-01"

# Longhorn node + disk re-registered
kubectl get node.longhorn.io -n longhorn-system worker-home-02 \
  -o jsonpath='{.status.diskStatus}' | jq
# Expect at least one disk with conditions Schedulable=True, Ready=True.

# Volumes back to healthy
kubectl get volume -n longhorn-system -o json | jq '.items[]
  | select(.spec.nodeID == "worker-home-02")
  | {name: .metadata.name, robustness: .status.robustness, state: .status.state}'
# Expect every volume robustness=healthy, state=attached (or detached if no
# consumer scaled up yet).

# Backup target still working
kubectl get backuptarget -n longhorn-system default \
  -o jsonpath='{.status.available}'
# Expect: true
```

Compare against `/tmp/worker-home-02.pre.yaml` and `/tmp/longhorn-volumes.pre.txt` from step 1 — node should be at the same Longhorn replica count it was before.

## Recovery (pessimistic path)

You land here when step 8 reported MISSING for the `longhorndata` VG (a disk was swapped, or `host_disks_action=overwrite` was deliberately run, or the disks themselves failed).

1. **Confirm what's gone.** `lsblk` on the host. If physical disks are missing, stop and replace them following `docs/storage-disk-runbook.md` first.

2. **Re-create the LVM substrate** (DESTRUCTIVE — wipes any residual data on the declared disks):
   ```bash
   cd ansible
   ansible-playbook --vault-password-file ansible-pass \
     --limit worker-home-02 \
     -e host_disks_action=overwrite \
     playbooks/poochella/infra/17-host/15-storage.yml
   ```
   Only proceed if you have confirmed pre-condition 2 above (backups exist). This step does not consult Longhorn — it carves disks immediately.

3. **Run step 9** (rejoin the cluster) so Longhorn sees the empty `/var/lib/longhorn`.

4. **Restore each volume from the NAS BackupTarget** via the Longhorn UI:
   - Longhorn UI → Backup → `<volume-name>` → Restore Latest Backup.
   - Restore Volume Name: match the original.
   - StorageClass: match the original (typically `longhorn`).
   - Repeat for every volume that had a replica on `worker-home-02`.

5. **Bind PVCs** to the restored volumes. If the original PVCs still exist in the cluster (because the workloads were just scaled to zero), Longhorn re-attaches automatically. If the PVCs were deleted, update the workload's Flux manifest to reference the restored volume name (see `docs/runbooks/longhorn-backup.md` for the restore flow detail).

6. **Scale workloads back up** and re-run the verification block above.

## Common failure modes

- **Preseed never fires.** Host iPXE-boots but stalls. Cause: `bootserv01` not serving the host file. Check `ansible bootserv01 -b -m shell -a 'ls /srv/http/hosts/ /srv/http/preseed/'`. Re-render with `just do-bootserv-config`. If MAC/IP reservations changed, also `just do-router-dhcp`.

- **k3s-agent won't start.** `ansible worker-home-02 -b -m shell -a 'journalctl -u k3s-agent -n 200 --no-pager'`. Usual cause: stale token. Re-decrypt with `just secret-decrypt vault_k3s_cluster_token` and confirm it matches what the server expects; the playbook re-templates it from the vault every run.

- **Longhorn volumes stuck in `Faulted` after rejoin.** `kubectl describe volume.longhorn.io <name> -n longhorn-system`. Most common: host-disks recreated the VG, replica metadata is gone. Follow the pessimistic path above (restore from backup).

- **`Host key verification failed`** on every ansible call after the reboot. Forgot step 6 — run `just ssh-refresh`.

- **Longhorn node shows the disk Unschedulable / Ready=False.** Usually a stale node CR from before `kubectl delete node` in step 3. Delete the Longhorn node CR (`kubectl delete node.longhorn.io worker-home-02 -n longhorn-system`) and wait for longhorn-manager to re-create it.

## Single-worker hazard reminder

With one `kube_workers` member, Longhorn `replica=1` means: **the data on `worker-home-02` has exactly one local copy and one NAS backup**. If the host dies, the data is gone unless a fresh backup is on `nas01`. Never start this runbook without re-confirming pre-condition 2.

Once a second worker comes online (Phase 2), Longhorn rebuilds the replica from the peer instead of from the NAS — the runbook structure stays the same, but the recovery time drops from "restore every volume" to "wait for replica sync."

## Cross-references

- `docs/runbooks/longhorn-backup.md` — BackupTarget + RecurringJob wiring; this runbook hard-depends on it.
- `docs/storage-disk-runbook.md` — single-disk swap on a live worker (different scenario; not a full re-image).
- `docs/poochella-stability-runbook.md` — incident history for the box (formerly `pve-home-02`, hardware crash loop in 2026-05).
- `ansible/inventory.yaml` — `worker-home-02` block (`debian_netboot.boot_macs`, `storage.disks` — the `select: boot` entry's `hw: {model, serial}` block is what the preseed resolves at install time).
- `ansible/group_vars/kube_workers.yml` — Longhorn-related node labels applied at k3s join.
- `justfile` — `do-foundation`, `do-host-init`, `do-bootserv-config`, `do-router-dhcp`, `disk-plan`, `ssh-refresh`.
