# Storage disk runbook — swap, grow, add (poochella)

Operational companion to `playbooks/poochella/infra/20-hypervisor/30-storage.yml`
and the `hypervisor-disks` role. Read the playbook header first; this
doc is the *people* steps around the automation.

## The one thing to internalise

The LVM-thin layer here is **single-disk and non-redundant by design.**
The carve playbook's contract on any disk replacement is *"re-initialise
a blank pool"* — it does **not** preserve that disk's bytes.

**Data safety lives at the Longhorn layer (a separate Flux repo), not
here.** Longhorn keeps `replica: 2` with hard zone anti-affinity
(`topology.kubernetes.io/zone = vm.proxmox_node`), so every volume has a
copy on **each physical node**. Pulling a data disk on one node is
survivable *because the other node still has the replica*. This repo's
only job is to make the empty re-init **safe and one-pass**; Longhorn
rebuilds the data.

> If a node's longhorn disk dies while the *peer* node is also down or
> its replica is degraded, that volume's data is gone. Verify peer
> replica health **before** any destructive disk op. That check is the
> whole runbook.

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
6. **Re-init:** `just do-storage` (or `--limit <node>`). It wipe-gates
   the new disk, carves it, rebuilds the LVM-thin pool, re-registers the
   PVE storage. Idempotent for every untouched disk on the node.
7. **Re-provision the worker disk + rejoin:** recreate the worker's data
   disk (`tofu apply` if the VM/disk was destroyed) and
   `kubectl uncordon <node>`.
8. **Longhorn rebuilds** the replica onto the fresh disk from the peer.
   Watch it reach `Healthy` before touching the *other* node.

**Never run a destructive disk op on both physical nodes at once.** One
node at a time, peer healthy in between — that is the entire HA story.

## B. Grow capacity without swapping (add a disk)

e.g. pve-home-02: add a 1 TB disk to extend `longhorn-data`.

1. Physically install the disk.
2. `just disk-plan` → copy the suggested selector block.
3. In `inventory.yaml`, add a new `storage.disks` entry whose partition
   reuses `vg: longhorndata / thinpool: longhornthin /
   pve_storage: longhorn-data` with a **new unique `label` partlabel**
   (e.g. `longhorn-hdd`). Add `wipe: force` if it shows signatures.
4. `just do-storage`. The `longhorndata` VG extends onto the new PV and
   `lvextend +100%FREE` grows `longhornthin` over it — one combined,
   larger `longhorn-data`. No VM/Longhorn disruption (purely additive at
   the LVM layer; nothing is rewritten).
5. To actually *use* the new space, raise the worker's
   `vm.data_disk_size` in `inventory.yaml` + `tofu apply`, then expand
   the Longhorn disk/volumes Flux-side. **Note:** replica-2 usable
   capacity is bounded by the *smaller* node — growing one node alone
   doesn't grow usable Longhorn capacity until the peer matches.

> ⚠ Mixing NVMe + HDD in one thin pool: extents that land on the HDD run
> at HDD speed and LVM can't pin Longhorn's hot data to the NVMe. It is a
> deliberate capacity-over-latency trade. To segregate, give the HDD its
> own `vg/thinpool/pve_storage` instead of reusing longhorndata (a
> one-line inventory change) and handle tiering Flux-side.

## C. The current pve-home-02 rebuild (2026-05-19)

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
`pvesm add nfs|pbs` path in the `hypervisor-disks` role when the NAS
lands; the runbook's step D references become live then.
