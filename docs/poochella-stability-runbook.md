# Poochella stability runbook

Incident + remediation record for the recurring "quorum blips" on the
poochella 3-node Proxmox/Ceph cluster. Written 2026-05-15.

> **Update 2026-05-16 — Ceph removed.** Storage was reworked to
> node-local LVM-thin (`vm-storage` → PVE `vms`, `longhorn` → PVE
> `longhorn-data`); the `ceph`/`ceph-csi` roles and their playbooks are
> now dormant/unwired. Consequently the Ceph-specific stopgaps recorded
> below are **moot** (no OSDs/mons exist): the mclock profile,
> `ceph-osd@.service` start-limit hardening, and `mon_max_pg_per_osd`
> tuning no longer apply. Removing Ceph eliminates the reboot-time
> backfill storms over the shared 1GbE and the mon-quorum coupling — a
> flapping *amplifier* is gone. **The hardware power-cycle root cause
> (Appendix B / `rma-evidence-pve-home-02-2026-05-15.txt`) is
> unaffected and still open** — this change is not a hardware fix, and
> node-local storage means a crashed node's VMs are down (no HA
> failover) until it returns.

## TL;DR

The "frequent quorum loss" is **not** a corosync/quorum design problem
and **not** (primarily) a network problem. The primary cause is
**`pve-home-02` hard-rebooting on its own every few-to-tens of minutes**
— a suspected hardware fault. The cluster only stays up because 2/3 is
still corosync + Ceph-mon quorum.

Update (evidence collected 2026-05-15, see Appendix B + `rma-evidence-pve-home-02-2026-05-15.txt`):
it is **not only pve-home-02**. All three identical refurbished HP
ProDesk 600 G4 DM units spontaneously power-cycle — `crash`-reboot
counts since 05-08: 01 = 3, **02 = 711 (looping)**, 03 = 4. pve-home-02
is a catastrophic outlier (a defective unit), but 01 & 03 crashing
near-simultaneously on 05-12 indicates an additional shared/batch cause
(power delivery or common 2018 firmware). Two prongs — see Appendix B.2.

A corosync QDevice was evaluated and **rejected**: it cannot help a node
that powers off, it does nothing for Ceph mon quorum, it is discouraged
for odd-node clusters, and `corosync-qnetd` is not packaged for the
FreeBSD-based OPNsense router anyway.

## Evidence

- `last -x reboot` / `journalctl --list-boots` on pve-home-02: 6 unclean
  ("- crash") reboots in <1 h on 2026-05-15.
- The crashed boot's journal ends mid-normal-operation on benign pmxcfs
  RRD log lines, then stops dead. No `panic` / `oom-kill` / `machine
  check` / `thermal` / `hung_task` / `soft lockup` / `Oops` anywhere in
  that boot's kernel log. `/sys/fs/pstore` empty.
- An instantaneous halt with **zero kernel trace** is the signature of a
  hard power event, not software/kernel/network.
- `EDAC ie31200: No ECC support` — consumer platform, no memory-error
  detection (HP OEM small-form-factor boxes).
- `lm-sensors` not installed → temperatures are currently blind.

Symptoms that masqueraded as a network issue: corosync
`link: host: 2 link: 0 is down` → ~2 min gap → rejoin, repeating; Ceph
mon `pve-home-02` and `osd.1` flapping. These line up exactly with the
crash → POST → boot cycle.

## Immediate operational stabilization (manual, reversible)

While pve-home-02 is unstable, stop Ceph from re-backfilling ~35 GiB on
every reboot (the backfill saturates the shared 1GbE and drags the
healthy nodes into corosync token timeouts too):

```bash
# on any healthy node (run as root):
ceph osd set noout            # stop auto out/rebalance of briefly-down OSDs
# optional, if HA is bouncing guests around:
#   ha-manager / migrate critical VMs off pve-home-02
# revert once pve-home-02 is fixed:
ceph osd unset noout
```

`noout` is cluster-wide and fully reversible. It does not stop a real
OSD from being marked down — it stops the *rebalance* churn.

## Root-cause fix: pve-home-02 hardware triage

This is physical and cannot be automated from here. In order of
likelihood for an untraced hard power-off on consumer SFF hardware:

1. **Power supply / power delivery.** Swap the PSU (or external brick).
   Check it is not on a shared/overloaded outlet that browns out under
   Ceph load. This is the single most likely cause.
2. **Thermal trip (THERMTRIP).** Open the case, clear dust from fans/
   heatsink, re-paste the CPU, confirm fans spin. Install monitoring so
   the next event is visible:
   ```bash
   apt-get install -y lm-sensors && sensors-detect --auto && sensors
   ```
3. **RAM (no ECC).** Run `memtest86+` overnight (Proxmox ISO / GRUB
   entry). Reseat DIMMs; test sticks individually.
4. **Secondary, only if 1–3 are clean:** BIOS/firmware update; pin a
   known-good kernel (currently `6.17.2-1-pve`, very new) via
   `proxmox-boot-tool kernel pin <older>` and observe.

Until the faulting part is found, treat pve-home-02 as untrusted: keep
`noout` set and do not place HA-critical VMs on it.

## Stopgaps implemented in this repo (damage control, not the fix)

These reduce the blast radius of each pve-home-02 reboot. They do **not**
fix the crashes.

| Change | Where | Effect |
|---|---|---|
| `osd_mclock_profile = high_client_ops` | `roles/ceph/defaults/main.yml`, applied in `roles/ceph/tasks/cluster.yml` (idempotent) | Recovery/backfill no longer starves client IO + corosync on the shared 1GbE when a node rejoins. |
| `ceph-osd@.service` start-limit removed + restart back-off | `roles/ceph/tasks/osd_hardening.yml` (drop-in `10-restart-hardening.conf`), wired into `03b-install-ceph.yml` | An OSD self-recovers whenever the mons become reachable again instead of dying permanently after ~15 min (the osd.2 failure mode). |
| `mon_max_pg_per_osd = 500` | `roles/ceph/defaults/main.yml`, applied in `roles/ceph/tasks/cluster.yml` (idempotent) | The 3-OSD cluster's pg_autoscaler grew `vms` past the default 250 cap, which silently blocked creating `kube-rbd` (`pveceph pool create` swallows the mon rejection and exits 0). Real fix is more OSDs. |

Pre-existing playbook bugs fixed in passing (each blocked `03b-install-ceph.yml` from completing idempotently):

- **`bootstrap.yml` mgr idempotency:** `ceph mgr dump` only lists *running* mgrs, so a created-but-stopped mgr (pve-home-01's was down) re-ran `pveceph mgr create` → hard fail. Now keys off the on-disk mgr dir and recovers a stopped mgr (clears systemd start-limit + starts it).
- **`cluster.yml` `rbd pool init` race:** runs immediately after `pveceph pool create`; now retries until the pool is openable.

Note: after `kube-rbd` is created the cluster shows a benign `too many PGs per OSD` HEALTH_WARN — an advisory for a 3-OSD cluster, not a blocker. It clears with more OSDs.

Apply with: `just do-ceph-init` (re-running `03b-install-ceph.yml` is
idempotent). Tunables: `ceph_osd_mclock_profile`,
`ceph_osd_start_limit_interval_sec`, `ceph_osd_restart_sec` in
`roles/ceph/defaults/main.yml`.

### Intentionally NOT implemented: corosync token-timeout tuning

Raising the corosync totem `token` timeout was considered and **dropped**.
It only buys patience for a *slow* peer; a peer that has *powered off*
is gone regardless of the timeout, so it would mask nothing real here
and add risk to `/etc/pve/corosync.conf`. Keep it on the shelf unless
the latent network issue below becomes the dominant problem after
pve-home-02 is fixed.

## Latent issue: single shared 1GbE NIC (separate from the crashes)

Every node has one 1GbE NIC (`lan0`/`nic0`) bridged into a flat `vmbr0`
on `10.1.1.0/24` carrying corosync ring0 (single link, no redundant
ring), Ceph `public_network` **and** `cluster_network`, VM traffic, and
PVE management. This is a real fragility that amplifies any disruption,
but it is not what makes pve-home-02 vanish.

Durable design for when hardware is added (e.g. a ~$15 USB3 2.5GbE
adapter per node):

1. Add a second NIC per node on a dedicated L2 segment / small switch.
2. Move corosync to its own link: add `ring1_addr` (knet link 1) on the
   second NIC — instant resilience even before re-IPing anything;
   `link_mode: passive` is already set.
3. Point Ceph `cluster_network` (replication/backfill — the bandwidth
   hog) at the second NIC; leave `public_network` on the first.
4. Encode the second interface + corosync link in `inventory.yaml` /
   the `hypervisor` role; bump `/etc/pve/corosync.conf` `config_version`
   when adding `ring1_addr` (edit on one node — pmxcfs replicates).

## Quick reference: is poochella flapping again?

```bash
# 1. Is a node crash-looping?  (the usual culprit)
ansible baremetal -b -m shell -a "uptime; last -x reboot | head -3"
# 2. corosync / Ceph state
ansible pve-home-01 -b -m shell -a "pvecm status; ceph -s"
# 3. If a node shows recent unclean reboots -> hardware triage above,
#    NOT corosync/QDevice/network tuning.
```

---

## Appendix A — Investigation log (how this was diagnosed)

Chronology, so this document stands alone as the incident record:

1. **Reported symptom:** "frequent quorum blips / losing quorum too
   often." Proposed fix: add a corosync QDevice on the OPNsense router.
2. **QDevice rejected** — it does nothing for Ceph mon quorum (separate
   Paxos), is discouraged for odd-node clusters, `corosync-qnetd` isn't
   packaged for FreeBSD/OPNsense, and it cannot fix the actual cause.
3. **Found `osd.2` on pve-home-01 down+out** — it had exhausted
   systemd's restart limit during a boot-time mon-unreachable window and
   sat dead ~2 days. Disk SMART clean. Recovered it → `HEALTH_OK`.
4. **Diagnosed the shared single-1GbE architecture** (corosync + Ceph
   public + Ceph cluster + VM traffic all on one NIC) — a real latent
   fragility, initially over-attributed as the primary cause.
5. **Correction:** while verifying, pve-home-02 went 100% unreachable.
   `journalctl --list-boots` / `last -x` showed it is **hard-rebooting
   every few-to-tens of minutes**. The corosync "link down → ~2 min →
   rejoin" cycles were pve-home-02's crash → POST → boot cycle. The
   network was a red herring for the *primary* symptom.
6. **Stopgaps implemented** (damage control only) + three pre-existing
   playbook idempotency bugs fixed in passing. Corosync token tuning
   deliberately left out (cannot help a powered-off node).

Durable lessons:

- Corosync link-down/rejoin and single-node Ceph mon/OSD flapping
  **masquerade** as network/quorum problems. Always check
  `journalctl --list-boots` / `last -x reboot` for an unclean-reboot
  loop **first**.
- An abrupt journal cutoff with **no** panic/OOM/thermal/MCE **and** an
  empty `/sys/fs/pstore` is the signature of a hardware power event, not
  software.
- **Identical declarative config across N nodes + only one failing
  isolates the fault to that unit's hardware.** That is also the RMA
  argument below.

---

## Appendix B — Hardware fault case for pve-home-02 (refurbished mini PC, for the vendor / RMA)

All three nodes are refurbished mini PCs of the same model, deployed and
configured identically. Only **pve-home-02** misbehaves. This appendix is
the evidence package to present to the seller/manufacturer.

### B.1 One-paragraph summary (adapt and send)

> I run three identical refurbished [MODEL] mini PCs as a cluster. All
> three run the same OS, kernel, and configuration (managed declaratively
> from version control — provably identical). Two of them (units with
> serials [01], [03]) have multi-day stable uptime under load. The third,
> serial **[02-SERIAL]**, **spontaneously power-cycles every few-to-tens
> of minutes**: the OS logs show normal operation that stops dead with
> **no shutdown sequence, no kernel panic, no out-of-memory, no thermal
> event, and no machine-check error**, and the firmware crash store is
> empty. **All three identical refurbished units exhibit this** (per-unit
> `crash`-reboot counts since 2026-05-08: unit [01]=3, unit
> **[02-SERIAL]=711 and currently crash-looping every few minutes**,
> unit [03]=4) — so this is a fleet/batch pattern, not a single anomaly.
> Unit [02-SERIAL] is a severe outlier (~100–200× the crash rate of its
> siblings) and needs repair/replacement; the lower-rate crashes on the
> other two — including units [01] and [03] crashing within ~1 minute of
> each other on 2026-05-12 — additionally point to a common defect
> and/or shared power-delivery issue across the batch. I am requesting
> (a) replacement of unit [02-SERIAL] and (b) investigation of the
> systemic reboot behaviour across all three units. Supporting logs
> attached (`rma-evidence-pve-home-02-2026-05-15.txt`).

### B.2 The argument: hardware power-loss, two prongs

**Correction to the original assumption:** it is *not* "only node 02."
The wtmp evidence (B.6) shows **all three** refurbished units
spontaneously power-cycle; 01 and 03 just do it rarely enough
(every few days, then long stable stretches) to go unnoticed, while 02
does it constantly. The honest, and stronger, case has two prongs:

- **Prong A — unit 02 is a defective unit (RMA target).** 711 unclean
  reboots vs 3–4 on its siblings, currently crash-looping every few
  minutes. Even within a misbehaving batch this is a ~100–200× outlier:
  a unit-specific acute hardware fault. Replace it.
- **Prong B — systemic across the batch.** Units 01 and 03 **crashed
  within ~1 minute of each other on Tue 2026-05-12 (~20:20–20:21)**.
  Independent per-unit hardware faults do not synchronise — that points
  to a *shared* cause: power delivery (UPS / PDU / outlet / circuit
  brownout) and/or a common firmware/model defect (all three on a 2018
  BIOS, never updated; non-ECC RAM).

What is ruled out, for both prongs (the events are hardware power loss):

| Possible cause | Ruled out by |
|---|---|
| User config / software | All 3 nodes configured by the same version-controlled Ansible/OpenTofu; OS, kernel, packages, tuning provably identical (B.3 #5). The failure is not correlated with any node-specific software. |
| Operating system / kernel bug | Identical kernel on all 3. A kernel bug would leave a panic/Oops — none present in any crashed boot (B.3 #4). (A common *firmware* defect is **not** excluded — see Prong B.) |
| Disk failure | `smartctl` on the boot SSD/NVMe: health PASSED, 0 reallocated/pending/uncorrectable sectors, 0 CRC errors (B.3 #6). |
| Out-of-memory / software thermal throttle | No `oom-kill`, no thermal/throttle lines anywhere in any crashed boot's kernel log (B.3 #4). |
| Clean/automated reboot (updates, HA fence) | No OS shutdown sequence before the cut-off; `last -x shutdown` shows **no** clean shutdown records (B.3 #2, #3). |
| **Remaining: hardware power loss** | Untraced instantaneous power loss is the classic signature. Prong A (unit 02): PSU / power-delivery / VRM / mainboard / RAM of that specific unit. Prong B (batch): shared power source, or a common firmware/board defect in the refurbished batch. Refurb-specific suspects: aged/under-spec PSU or power brick, failing/bulging mainboard capacitors, poorly reseated or mismatched refurb RAM, cold-solder joints, thermal paste not reapplied, un-updated 2018 firmware (hardware THERMTRIP also cuts power with no OS log — see B.4). |

### B.3 Evidence to collect and attach

Run as root. Capture the output of each into a file and attach it to the
RMA ticket. Run the cross-node ones so the vendor sees 01/03 as the
controlled baseline.

**1. Headline artifact — stability side-by-side across all 3 units:**
```bash
ansible baremetal -b -m shell -a "echo \"== \$(hostname) ==\"; uptime -p; uptime -s; echo -n 'unclean reboots in wtmp: '; last -x reboot | grep -c crash; echo -n 'boot epochs on disk: '; journalctl --list-boots --no-pager | wc -l"
```
Observed 2026-05-15: 01 = 3 crashes (stable ~1.8 d since 05-13);
03 = 4 crashes (stable ~12 h since 05-15 01:32); **02 = 711 crashes,
~12 min uptime, still looping**. The contrast (02 two orders of
magnitude worse, yet all three non-zero) is itself the headline.

**2. The reboot history on unit 02 (frequency + unclean markers):**
```bash
journalctl --list-boots --no-pager      # many short-lived boot epochs
last -x reboot                          # each line ends "- crash" = unclean
last -x shutdown                        # NONE = it never shut down cleanly
```

**3. Proof it was NOT an OS-initiated reboot (no shutdown sequence):**
```bash
# Unit 02 — the boot before the latest crash; ends mid-operation:
journalctl -b -1 -n 40 --no-pager
# Contrast: a CLEAN reboot shows the full "Stopping … / Reached target
# Shutdown / systemd-shutdown: Syncing" sequence. The crash boots have
# none of that — they just stop. (Note: 01/03's last boots also ended
# uncleanly, so use a known-clean reference: do a manual `reboot` on a
# healthy node, or see pve-home-03's 2026-05-10 18:36 clean shutdown.)
```

**4. Proof it was NOT software (panic / OOM / thermal / MCE):**
```bash
journalctl -k -b -1 --no-pager | grep -iE \
  'panic|BUG:|oom-kill|out of memory|machine check|\bmce\b|hardware error|thermal|throttl|hung_task|soft lockup|Oops|general protection|RIP:' \
  || echo 'NONE — no software/kernel fault logged before the power loss'
ls -la /sys/fs/pstore/                  # empty = no firmware/kernel crash captured
```

**5. Hardware identity — proves the units are the same model & the
config is a controlled variable (vendor needs serials/BIOS):**
```bash
dmidecode -t system        # Manufacturer / Product Name / Serial Number / UUID
dmidecode -t baseboard     # board model + serial
dmidecode -t bios          # BIOS vendor / version / release date
dmidecode -t processor | grep -E 'Version|Max Speed'
dmidecode -t memory | grep -E 'Manufacturer|Part Number|Serial Number|Size|Speed|Rank'
uname -r; grep PRETTY /etc/os-release
```
Run on all three. Identical model/BIOS/kernel across nodes is itself
evidence: the only uncontrolled variable is the physical unit.

**6. Disk ruled out (include for completeness):**
```bash
smartctl -H -A /dev/sda
```

### B.4 Make the next crash conclusive (thermal capture)

A hardware thermal trip (THERMTRIP) cuts power instantly and the OS logs
**nothing** — indistinguishable in-log from a PSU failure. External temp
logging disambiguates: if temps are normal right up to a crash, that
**rules out thermal and strengthens the PSU/board case**.

```bash
apt-get install -y lm-sensors
sensors-detect --auto
# lightweight temp recorder (make it a systemd unit for persistence):
cat >/etc/systemd/system/temp-logger.service <<'EOF'
[Unit]
Description=Poochella temp logger (RMA evidence)
[Service]
ExecStart=/bin/sh -c 'while true; do echo "$(date -Is) $(sensors -u 2>/dev/null | tr "\n" " ")"; sleep 30; done'
StandardOutput=append:/var/log/poochella-temps.log
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now temp-logger
```

### B.5 Ongoing dossier (accumulate dated evidence)

Manufacturers want frequency and dates. This builds a clean exhibit
over days — "unit 02 logged N spontaneous power-loss reboots between
DATE and DATE; units 01 & 03 logged zero over the same period under
identical load":

```bash
# /etc/cron.d/poochella-reboot-watch  (install on each baremetal node)
*/10 * * * * root { date -Is; echo "uptime: $(uptime -p) (since $(uptime -s))"; last -x reboot | head -1; } >> /var/log/poochella-reboot-watch.log 2>&1
```

### B.6 Exhibit — what was observed on 2026-05-15 (pve-home-02)

Concrete capture to include verbatim with the RMA:

```
# journalctl --list-boots  (excerpt) — 6 boots in under one hour:
 -5  …  Fri 2026-05-15 12:00:55 EDT  →  12:08:32 EDT   (~8 min)
 -4  …  Fri 2026-05-15 12:10:12 EDT  →  12:17:22 EDT   (~7 min)
 -3  …  Fri 2026-05-15 12:19:07 EDT  →  12:20:09 EDT   (~1 min)
 -2  …  Fri 2026-05-15 12:22:05 EDT  →  12:32:12 EDT   (~10 min)
 -1  …  Fri 2026-05-15 12:34:28 EDT  →  12:53:52 EDT   (~19 min)
  0  …  Fri 2026-05-15 12:56:03 EDT  →  still running

# last -x reboot:
reboot system boot 6.17.2-1-pve  Fri May 15 12:55 - still running
reboot system boot 6.17.2-1-pve  Fri May 15 12:34 - crash
reboot system boot 6.17.2-1-pve  Fri May 15 12:21 - crash
reboot system boot 6.17.2-1-pve  Fri May 15 12:18 - crash

# Last lines of boot -1 before the power loss — benign, then nothing:
…12:53:52 pmxcfs[948]: [status] notice: RRD update error … (normal noise)
   <journal ends here; no shutdown sequence, no panic>

# Kernel log of boot -1, filtered for fault signatures: NONE
# /sys/fs/pstore: empty
# Platform: EDAC ie31200 "No ECC support" (consumer board, no memory
#   error reporting — RAM faults would be silent; memtest86+ needed to
#   exclude RAM). Kernel 6.17.2-1-pve. Units 01 & 03: stable, no
#   unclean reboots, same kernel and workload.
```

Sibling-unit baseline (pve-home-01, captured same day): single boot,
multi-hour uptime, `ceph-mon` active as quorum leader, zero `crash`
entries in `last` — same model, same software, no fault.

