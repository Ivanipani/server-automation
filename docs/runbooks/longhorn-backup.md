# Longhorn BackupTarget (nas01 NFS) — Flux-side hand-off

## What this document covers

The Longhorn install in this cluster lives in a separate Flux repo (this repo manages substrate only — host disks, k3s, NFS exports, etc.). This document describes the **Flux-side** configuration required to point Longhorn at the `longhorn-backup` NFS share on `nas01` so workload volume data can be backed up off-box.

This repo owns:
- The `longhorn-backup` NFS share on `nas01` (declared at `nas01.storage.shares[].name == longhorn-backup` in `ansible/inventory.yaml`; reconciled by `ansible/playbooks/poochella/infra/15-nas/30-storage.yml`).
- The NFS export rules on that share (currently LAN-wide `10.1.1.0/24` RW with `all_squash`).
- The 1 TiB quota on the share.

This repo does NOT own:
- The Longhorn install itself.
- The `BackupTarget` CRD (lives in the Flux repo).
- Recurring backup CronJob / Backup CRDs.
- Volume-level restore operations.

## Pre-conditions

1. The `longhorn-backup` share exists on DSM and exports NFSv4.1. Verify:
   ```bash
   ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/15-nas/25-storage-plan.yml
   # Look for `"name": "longhorn-backup"` in the output.
   ```
2. The `worker-home-02` baremetal worker can reach `nas01.lan:2049/tcp` (NFS). Verify:
   ```bash
   ansible worker-home-02 -m shell -a 'showmount -e nas01.lan' --become
   # Should list /volume1/longhorn-backup
   ```
3. Longhorn is installed in `longhorn-system` namespace via the Flux repo.

## Flux-side configuration

### BackupTarget

Add a `BackupTarget` resource (or update the existing default one) so Longhorn knows where to put backups. Apply via the Flux repo:

```yaml
apiVersion: longhorn.io/v1beta2
kind: BackupTarget
metadata:
  name: default
  namespace: longhorn-system
spec:
  backupTargetURL: "nfs://nas01.lan:/volume1/longhorn-backup"
  # No credentials needed — NFS exports are LAN-IP-scoped (no AUTH_SYS user
  # mapping per share; `all_squash` → DSM admin on the server side).
  credentialSecret: ""
  # Check connectivity every 5min; default is 5min but pin it explicitly
  # so the value is grep-able from kubectl.
  pollInterval: "5m0s"
```

Apply via the Flux repo's normal reconcile path; do NOT `kubectl apply` it directly (Flux will fight the change).

After Flux reconciles, verify:

```bash
kubectl get backuptarget -n longhorn-system default -o yaml | yq '.status'
# Expect:
#   available: true
#   conditions:
#   - type: Unavailable
#     status: "False"
```

If `available: false` or `lastSyncedAt` is stale, inspect the longhorn-manager pod logs on `worker-home-02`:

```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=200 | grep -i backup
```

Common failure modes:
- `permission denied` from the NFS mount: the worker's IP isn't in the share's NFS rule list. Fix in `ansible/inventory.yaml` (nas01.storage.shares[longhorn-backup].nfs.rules) then re-run `15-nas/30-storage.yml`.
- `connection refused`: nas01 NFS service is off. Check DSM → Control Panel → File Services → NFS (or run `15-nas/20-baseline.yml`).
- `stale file handle`: DSM was rebooted; the longhorn-manager DaemonSet pod needs to be restarted to re-mount.

### RecurringJob (scheduled backups)

Without recurring jobs, no backups happen automatically — `BackupTarget` only declares WHERE backups go, not WHEN. Define a per-volume backup schedule:

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  cron: "0 3 * * *"            # daily at 03:00 UTC
  task: "backup"
  groups:
    - default                  # applies to volumes with the `recurring-job.longhorn.io/default: enabled` label
  retain: 7                    # keep last 7 backups per volume
  concurrency: 2
```

Then label each volume that should be backed up:

```bash
kubectl label volume.longhorn.io -n longhorn-system <volume-name> \
  recurring-job-group.longhorn.io/default=enabled --overwrite
```

Or more commonly, label PVCs and let Longhorn propagate the label to the underlying volume via Flux-managed manifests in your workload directories.

### Verify a backup landed on the NAS

After the cron fires (or trigger one manually via Longhorn UI → Volume → Create Backup), the NAS should show backup chunks under `/volume1/longhorn-backup/backupstore/`:

```bash
ansible pve-home-01 -m shell -a 'ls /mnt/nas/build-artifacts/.. 2>/dev/null; ls /mnt/nas | head' --become
# Note: longhorn-backup is NOT mounted on hypervisors today — only on the
# baremetal worker. Inspect via DSM File Station instead:
# https://nas01.lan:5001/?launchApp=SYNO.SDS.App.FileStation3.Instance#/volume1/longhorn-backup
```

To browse from the LAN without DSM, mount it ad-hoc:

```bash
sudo mount -t nfs4 nas01.lan:/volume1/longhorn-backup /mnt/longhorn-inspect
ls -R /mnt/longhorn-inspect/backupstore/
```

Longhorn lays out backups as `backupstore/volumes/<two-hex-prefix>/<volume-name>/blocks/...` plus `backups/backup_<id>.cfg` per backup. Each backup is content-addressed; chunks are deduplicated within a volume's backup history.

### Restore from a backup (after a worker re-image)

When `worker-home-02` is re-imaged (per `docs/runbooks/rebuild-worker.md`, when that runbook exists post-Phase 1), the Longhorn replicas on its local disk are gone. Restore is via the Longhorn UI:

1. Longhorn UI → Backup → `<volume-name>` → Restore Latest Backup → pick a target Volume name + StorageClass.
2. Bind a PVC to the restored Volume via the workload's Flux manifest update.
3. Scale the workload back up.

For automation, the `BackupBackingImage` and `VolumeRestoreRecurringJob` CRDs can be Flux-managed, but those are out of scope here.

## Pre-condition for the worker-rebuild runbook

The worker-rebuild runbook (`docs/runbooks/rebuild-worker.md`, Phase 1) hard-gates on:

```bash
# Must return Available: true
kubectl get backuptarget -n longhorn-system default -o jsonpath='{.status.available}'

# Every volume on worker-home-02 must have a backup younger than N hours
kubectl get volume -n longhorn-system -o json | jq '.items[]
  | select(.spec.nodeID == "worker-home-02")
  | {name: .metadata.name, lastBackupAt: .status.lastBackup}'
```

If either check fails, the runbook BLOCKS and instructs the operator to either:
1. Wait for the next RecurringJob fire (and confirm it succeeded), OR
2. Trigger a one-shot backup of every relevant volume manually via the Longhorn UI before proceeding.

## Single-worker hazard (today)

With only one `kube_workers` member (`worker-home-02`), Longhorn `replica=2` collapses to one effective replica on that node. If the worker dies BEFORE a backup has run, **the data is gone** — there is no peer replica to rebuild from. The NAS-backed BackupTarget is the *only* durable copy.

When a second worker comes online (post-Phase 2), `replica=2` becomes a real second copy on a different node, and the BackupTarget becomes belt-and-braces instead of life support.
