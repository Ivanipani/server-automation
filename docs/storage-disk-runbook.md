# Storage disk runbook — swap, grow, add (poochella)

Operational companion to `playbooks/poochella/infra/17-host/15-storage.yml`
(local LVM substrate, all physical hosts — including the PVE-only
`pvesm add lvmthin` publication, folded into the `host-disks` role's
`tasks/pve_register.yml`). Read the playbook + role headers first; this
doc is the *people* steps around the automation.

## The one thing to internalise

On **workers**, each physical disk is its **own plain-ext4 mount** under
`/var/lib/longhorn-disks/<label>` = its **own Longhorn disk** (no LVM, no
spanning pool). On **hypervisors**, the boot tail is still an LVM-thin
`vms` pool. Either way the layer is **non-redundant by design** and the
carve contract on any disk replacement is *"re-initialise empty"* — it
does **not** preserve that disk's bytes.

**Data safety lives at the Longhorn layer (a separate Flux repo), not
here.** Longhorn keeps `replica: 2` with hard zone anti-affinity
(`topology.kubernetes.io/zone = vm.proxmox_node`), so every volume has a
copy on **each physical node**. Pulling a data disk on one node is
survivable *because the other node still has the replica*. With per-disk
Longhorn disks, losing one disk only loses **that disk's** replicas (the
node's other disks keep serving) — Longhorn rebuilds them from the peer.

> If a node's disk dies while the *peer* node is also down or its replica
> is degraded, that volume's data is gone. Verify peer replica health
> **before** any destructive disk op. That check is the whole runbook.

## Migrating an existing worker to per-disk mounts (one-time)

Going from the old single `longhorndata`/`longhornthin` spanning pool to
per-disk direct ext4 is **destructive** to that node's Longhorn data (the
pool is torn down). It is recovered from the peer by Longhorn. One node
at a time, peer healthy in between.

1. **Verify peer replicas healthy** (see step 2 of section A).
2. **Drain** the node (`kubectl cordon` + `drain`).
3. **Nuke-first (critical — partlabels are REUSED):** the wipe gate
   skips a disk that already carries one of our partlabels, so a stale
   `part-alpha/beta/gamma` would make the carve *skip* and leave a live
   `LVM2_member` partition that Pass-4 mkfs then refuses. Before the
   recarve, on the node destroy the old pool + signatures:
   ```bash
   vgremove -f longhorndata        # drop the old VG (if present)
   # each NON-boot data disk — whole-disk zap is fine:
   wipefs -a /dev/<data-disk>; sgdisk --zap-all /dev/<data-disk>
   # the boot disk: ONLY wipe the tail partition, never the whole disk:
   wipefs -a /dev/disk/by-partlabel/part-alpha
   ```
4. **Recarve** (see section A step 6 for the exact command).
5. **Uncordon**; Longhorn rebuilds replicas onto the new per-disk mounts.
6. **Flux lockstep:** register each `/var/lib/longhorn-disks/<label>` as
   an explicit Longhorn disk and turn the default-disk mechanism OFF
   (the `create-default-disk` label was removed in
   `group_vars/kube_workers.yml`). Until that lands the node has no
   Longhorn disks (safe — nothing schedules onto root).

## Selectors recap

Disks are declared in `inventory.yaml` `storage.disks[].select` by
**stable attribute**, never `/dev/disk/by-id`:

- `select: boot` — auto-detected PVE boot disk (the `pve` VG's PV).
- `select: { model: "...", serial: "..." }` — one exact physical drive.
- `select: { min_size_gib: 900, rotational: false }` — attribute match.

A non-`boot` selector **must resolve to exactly one** non-boot,
non-removable disk; 0 or >1 is a hard preflight failure. Run
`just disk-plan` to see every disk and a paste-ready skeleton.

`just disk-plan` is **read-only** and safe to run anytime.

---

## A. Swap a failed/old disk for an identical-or-larger one

Goal: zero data loss, minimal disruption.

1. **Identify** which Longhorn worker uses the disk. Data disks back
   `longhorn-data`; the worker pinned to that node is in `inventory.yaml`
   (`kube-worker-01` → `pve-home-02`, `kube-worker-02` → `pve-home-01`).
2. **Verify the peer replica is healthy** (Longhorn UI / `kubectl -n
   longhorn-system get volumes`): every volume with a replica on the
   affected node must show a second **healthy** replica on the *other*
   physical node. Do not proceed until it does.
3. **Drain** the worker on the affected node:
   `kubectl cordon <node>` then `kubectl drain <node>
   --ignore-daemonsets --delete-emptydir-data`. Longhorn now serves from
   the peer replica.
4. **Power off** the node (or just hot-swap if the bay supports it),
   physically replace the disk.
5. **Selector check:**
   - Replacement is the **same class** (≈same size, same rotational):
     the attribute selector still matches → **no inventory edit**.
   - Replacement is **larger**: if the selector is `min_size_gib`-based,
     still matches → no edit. The thin pool auto-grows (play 3 runs
     `lvextend +100%FREE` onto the new space).
   - Selector was `serial`-based, or now ambiguous: run
     `just disk-plan`, update that one disk's `select:` in
     `inventory.yaml`.
   - New disk carries old signatures (very common for a pulled drive):
     add `wipe: force` to **that disk's** entry (scoped, deliberate).
6. **Re-init** (there is no `just` recipe for the destructive carve; run
   it explicitly, scoped to the one node):
   ```bash
   cd ansible
   ansible-playbook --vault-password-file ansible-pass --limit <node> \
     -e host_disks_action=overwrite \
     playbooks/poochella/infra/17-host/15-storage.yml
   ```
   It wipe-gates the new disk, carves it, and (workers) builds the
   per-disk ext4 mount / (hypervisors) rebuilds the LVM-thin `vms` pool.
   Idempotent for every untouched disk on the node.
7. **Re-provision the worker disk + rejoin:** recreate the worker's data
   disk (`tofu apply` if the VM/disk was destroyed) and
   `kubectl uncordon <node>`.
8. **Longhorn rebuilds** the replica onto the fresh disk from the peer.
   Watch it reach `Healthy` before touching the *other* node.

**Never run a destructive disk op on both physical nodes at once.** One
node at a time, peer healthy in between — that is the entire HA story.

## B. Grow capacity on a worker (add a disk)

Workers are per-disk direct ext4 now, so adding capacity = adding **one
more Longhorn disk**, not growing a pool.

1. Physically install the disk.
2. `just disk-plan` → confirm it resolves; grab model/serial.
3. In `inventory.yaml`, add a new `storage.disks` entry for it with the
   **next unused ordinal `label`** (alpha→beta→gamma→…), `size: "0"`, a
   `mount: { path: /var/lib/longhorn-disks/<label>, fstype: ext4 }`, and
   `wipe: force` (disposable replica disk). NO vg/thinpool.
4. Recarve the node (section A step 6). The carve is additive: untouched
   disks are no-ops; the new disk gets its own ext4 mount.
5. **Flux:** register `/var/lib/longhorn-disks/<label>` as a new Longhorn
   disk on that node. **Note:** replica-2 usable capacity is bounded by
   the *smaller* node — growing one node alone doesn't grow usable
   Longhorn capacity until the peer matches.

> Per-disk mounts make tiering trivial: tag the NVMe-backed and
> HDD-backed Longhorn disks differently Flux-side and schedule hot
> volumes onto the NVMe disks. (The old single-pool model couldn't —
> HDD extents dragged the whole pool.)

> ⚠ The LVM-thin grow path (`lvextend +100%FREE`) now applies only to a
> hypervisor's `vms` pool, not to workers.

## C. The pve-home-02 rebuild (2026-05-19) — HISTORICAL, superseded

> ⚠ Describes the old single spanning `longhorndata`/`longhornthin` pool
> model and pre-rename hostnames. Superseded by the per-disk direct-ext4
> model (see "The one thing to internalise" + the migration section
> above). Kept for context only.

Operator is taking **all VMs and Longhorn workers down** for this, so it
is a clean destructive rebuild, not a live swap:

- boot NVMe (~250 GB) → `vms` (idempotent; existing pool preserved).
- new ~1 TB NVMe → `longhorn-data` (`wipe: force` — stale prior-install
  GPT).
- freed ~1 TB WDC HDD → **same** `longhorn-data` (`wipe: force` — it was
  the old longhorn disk; its live `vm-104-disk-0` is recoverable from
  the Longhorn replica on `pve-home-01`/`kube-worker-02`, and the
  workers are down anyway).

Result: one `longhorndata` VG / `longhornthin` pool spanning **both**
the NVMe and the HDD (~1.8 TB raw, thin-provisioned).

Run: `just disk-plan` (sanity) → review → `just do-storage`.

---

## D. Forward-looking: Synology NAS (8 TB) as cold storage / backup

When the NAS comes online it slots in as the *real* "swap without data
loss" safety net for the non-Longhorn case (Longhorn already self-heals
via replicas; the NAS covers VM root disks and gives an offline copy):

- It is **not** an LVM-thin pool. It is a Proxmox storage of type
  `nfs`/`cifs` (a `dir`-style target) or a Proxmox Backup Server
  datastore — i.e. a *backup/restore* target, not a carve target.
- The `storage.disks` selector schema is intentionally scoped to local
  whole disks. A NAS target will be a **separate** declaration (planned:
  a `storage.network:` / backup-target section, registered with
  `pvesm add nfs|pbs …`) so it does not collide with disk selection and
  needs no second redesign.
- Runbook integration: before a destructive op on a node, take a
  `vzdump`/PBS backup of any non-Longhorn-protected guest to the NAS;
  restore from it if a re-init loses something Longhorn wasn't covering.

Status: **not yet implemented** (NAS not online). Tracked here so the
schema reservation and the runbook step are explicit. Implement the
`pvesm add nfs|pbs` path in the `host-disks` role when the NAS
lands; the runbook's step D references become live then.
