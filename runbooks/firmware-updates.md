# Firmware Updates

Keeping every firmware-bearing thing in the homelab current. Patching is
**deliberate, never unattended** — same philosophy as the
`apt-no-auto-upgrades` role. Nothing here applies updates on a schedule;
the operator does, after looking at what's pending.

Four vendor paths, because no single tool reaches everything:

| Component                             | Tool / surface                | Automated? |
| ------------------------------------- | ----------------------------- | ---------- |
| Baremetal Linux components            | `fwupd` / LVFS                | yes        |
| CPU microcode (Intel / AMD)           | `intel-microcode` / `amd64-microcode` apt package | yes (`just firmware-plan` surfaces; apt applies) |
| HP MP9 G2 system BIOS (`pve-home-01`) | HP SoftPaq → FAT32 USB → F10  | no         |
| Samsung NVMe firmware                 | `nvme-cli` + Samsung firmware files | no   |
| Other non-LVFS devices (HDDs, generic SSDs, etc.) | vendor tooling   | no         |
| Synology NAS                          | DSM Control Panel             | no         |
| OPNsense router                       | OPNsense web UI               | no         |

The `fwupd` and microcode paths are the ones `just firmware-plan`
surveys; the rest are vendor-managed manual procedures documented
below. **A clean `firmware-plan` run does not mean every firmware in
the fleet is current** — only the two automated paths above. See "What
the plan does and does not verify" below.

## Baremetal Linux components (fwupd / LVFS)

Reaches NVMe SSDs, NICs, TPMs, integrated GPUs, dock controllers, and
(on hardware that supports UEFI capsule updates) the system BIOS itself.
Driven by the Linux Vendor Firmware Service.

`fwupd` is installed on every baremetal by `host-base` (via the
`firmware` role), and the LVFS remote is re-asserted as enabled on
every host-base run. Nothing else runs automatically.

### Day-to-day

```sh
just firmware-plan         # READ-ONLY: refresh + report across all baremetal
just firmware-update <host>  # DESTRUCTIVE: apply, ONE host at a time
```

### What the plan prints

`just firmware-plan` shells out to
`playbooks/poochella/infra/17-host/60-firmware-plan.yml`, which
runs `fwupdmgr refresh --force` and then `apt-get update`, and prints
four sections per host:

1. **`FWUPD: UPDATES AVAILABLE`** — LVFS has a newer firmware than what
   the device reports running. Apply with `just firmware-update <host>`.
2. **`FWUPD: LVFS-CURRENT`** — fwupd marks the device `updatable` and
   LVFS returned no newer release. **Read this as "fwupd has the
   protocol to flash this device and LVFS didn't return an update
   today"** — it does NOT prove the vendor has published current
   firmware for the device at all. If the vendor never uploaded to
   LVFS, the device sits here forever looking healthy.
3. **`FWUPD: OUTSIDE REACH`** — the device exists but fwupd cannot
   drive an update: either missing the `updatable` flag (CPUs, NVIDIA
   GPUs, Mellanox NICs, USB sticks, etc.) or carrying a hard
   `UpdateError` (e.g. `No vendor ID set` on generic SSDs like the
   Timetec in `pve-home-01`). These need vendor tooling; LVFS is not
   the source of truth for them.
4. **CPU microcode** — Intel / AMD microcode is firmware shipped as
   the `intel-microcode` / `amd64-microcode` apt package and applied
   from initrd at boot. The plan refreshes the apt cache and reports
   installed vs. candidate version, flagging `UPDATE AVAILABLE` /
   `MISSING` / `current`. Applies via `apt install --only-upgrade` +
   reboot — not via `just firmware-update`.

`just firmware-update <host>` runs `60-firmware-update.yml` with
`--limit <host>`. The playbook itself refuses if more than one host
ends up in scope (defence in depth on top of the recipe's positional
arg). It only handles section 1 (fwupd updates) — microcode upgrades
go through `apt install --only-upgrade intel-microcode` (or
`amd64-microcode`) by hand, followed by a reboot.

### Reboot handling

Some updates (notably NVMe firmware, system firmware, CPU microcode)
only take effect on the next boot. `fwupdmgr` stages firmware and
reports `needs-reboot` in its output; microcode is staged into the
initrd by the apt postinst hook. We deliberately do NOT reboot
automatically — drain the k3s node first if it's carrying Longhorn
replicas, then reboot manually.

### Adding a new baremetal

Nothing extra to do. The `firmware` role runs as part of `host-base`,
which the `17-host` tier applies to every member of the `physical`
group. New baremetal → `just do-host-init` → fwupd is there.

### What the plan does and does not verify

What it **does** verify:

- **fwupd LVFS-CURRENT** devices: LVFS does not currently advertise a
  newer firmware for that device. (Note caveat above — this is not the
  same as "the vendor has published current firmware to LVFS"; only
  that LVFS didn't return an update today.)
- **CPU microcode**: installed apt package version vs. the candidate
  in your refreshed apt index. Strong: this is what Spectre-class
  fixes ship through.

What it **does NOT** verify:

- Firmware on any device in the `FWUPD: OUTSIDE REACH` section.
  Silence there is not currency.
- Samsung NVMe firmware in detail — even though Samsung NVMes can land
  in `LVFS-CURRENT`, Samsung's publishing cadence to LVFS is sparse;
  pair this with Samsung's own update notifications.
- HP MP9 G2 system BIOS — Skylake-era HP business desktops don't
  expose UEFI capsule updates (`fwupdmgr` reports "UEFI capsule
  updates not available or enabled in firmware setup"), so the system
  firmware does not even appear in the device list. Handled via the
  vendor-USB path below.
- Synology DSM, DSM packages, OPNsense — separate vendor mechanisms.
  See cadence table at the bottom.
- Guests (VMs / LXCs) — virtual devices presented by Proxmox have no
  firmware of their own; out of scope.

## HP MP9 G2 system BIOS (`pve-home-01`)

HP only publishes the BIOS as a Windows SoftPaq `.exe` — but the
`.exe` is a 7-zip self-extractor that opens fine on Linux, and the BIOS
itself updates from a FAT32 USB at POST time via HP's built-in
**F10 → Update System BIOS** menu. No Windows host needed.

### One-time setup on `worker-home-02` (the dev box)

```sh
sudo apt install -y p7zip-full
```

### Update procedure

1. **Check HP's support page for a SoftPaq newer than what's running.**
   Look up by SKU `W5Y31UA` or model `MP9 G2 Retail System`, BIOS
   family `N21`. The latest SoftPaq's `SP######.cva` will list its
   superseded predecessor — if it does not supersede the SoftPaq you
   already have, there's nothing new to flash.

2. **Drop the SoftPaq onto `worker-home-02`** and confirm the version
   inside is actually newer than what's installed:

   ```sh
   scp sp######.exe worker-home-02:/tmp/
   ssh worker-home-02

   7z x -y -o/tmp/sp###### /tmp/sp######.exe
   cat /tmp/sp######/History.txt | head        # release notes
   grep -i version /tmp/sp######/SP######.cva  # version metadata
   ls -la /tmp/sp######/*.bin                  # the raw firmware
   ```

   Then on `pve-home-01`:

   ```sh
   ansible pve-home-01 -m shell -a 'dmidecode -s bios-version' --become
   ```

   If the `.bin` version == the dmidecode version, stop — you already
   have it.

3. **Prep a FAT32 USB on `worker-home-02`.** Identify the right device
   carefully (`lsblk -o NAME,SIZE,TYPE,TRAN,VENDOR,MODEL,SERIAL,RM` —
   serial is the safest disambiguator). For a PNY 32 GB stick on
   `/dev/sdX`:

   ```sh
   sudo wipefs -a /dev/sdX
   sudo parted -s /dev/sdX mklabel msdos mkpart primary fat32 1MiB 100%
   sudo mkfs.vfat -F32 -n HPBIOS /dev/sdX1
   sudo mkdir -p /mnt/hpusb && sudo mount /dev/sdX1 /mnt/hpusb

   # Primary path the BIOS reads at update time:
   sudo mkdir -p /mnt/hpusb/EFI/HP/BIOS/New
   sudo cp /tmp/sp######/*.bin /mnt/hpusb/EFI/HP/BIOS/New/
   [ -f /tmp/sp######/*.sig ] && sudo cp /tmp/sp######/*.sig /mnt/hpusb/EFI/HP/BIOS/New/

   # Recovery copy — same files in HP's legacy location, used by
   # the BIOS's emergency-recovery path if a flash bricks:
   sudo mkdir -p /mnt/hpusb/Hewlett-Packard/BIOS/Current
   sudo cp /mnt/hpusb/EFI/HP/BIOS/New/* /mnt/hpusb/Hewlett-Packard/BIOS/Current/

   sudo umount /mnt/hpusb && sudo eject /dev/sdX
   ```

4. **Flash on `pve-home-01`.**
   - Drain any workload off the box (it's the etcd blast radius — all
     three k3s control plane VMs live there).
   - Shut down cleanly, insert the USB.
   - Power on, mash **F10** for BIOS setup.
   - Navigate: `File` → `Update System BIOS` → select the file from the
     USB. (If F10 doesn't offer it, **F2** during POST opens HP
     Diagnostics, which also has a BIOS update option.)
   - Do NOT power off during the flash. It typically takes 2-5 minutes
     and reboots itself when done.

5. **Verify.** After boot:

   ```sh
   ansible pve-home-01 -m shell -a 'dmidecode -s bios-version ; dmidecode -s bios-release-date' --become
   ```

### Why fwupd doesn't work for this BIOS

Confirmed against current hardware (`fwupdmgr get-plugins`):

```
WARNING: UEFI capsule updates not available or enabled in firmware setup
```

HP enabled UEFI capsule support on later generations, but not on the
Skylake-era (2016) MP9 G2 / EliteDesk 800 G2 DM family. Vendor-USB is
the only path on this hardware.

## Synology NAS

DSM auto-checks for OS updates but does not auto-apply them. Approve
manually:

- DSM web UI → **Control Panel** → **Update & Restore** → **DSM Update**
- Review the release notes, then **Download** + **Update Now**
- Cadence: monthly check is fine; critical security DSMs warrant
  same-week patching

Package updates (Container Manager, Snapshot Replication, etc.):
**Package Center** → **Installed** → look for the orange "Update"
badges. Apply during a maintenance window since some packages restart
services.

## OPNsense router

OPNsense ships its own firmware update path. Manual + interactive:

- OPNsense web UI (`https://10.1.1.1`) → **System** → **Firmware** →
  **Status** → **Check for updates**
- Review the changelog, then **Update**
- Cadence: OPNsense ships ~2 major releases / year + monthly business
  updates. Apply business updates monthly; majors when the homelab can
  tolerate a `~5`-minute internet blip.

This is the same router that runs dnsmasq + Unbound for the fleet, so
plan a window where briefly losing LAN DHCP/DNS is OK.

## Applying CPU microcode updates

When `firmware-plan` reports `intel-microcode` or `amd64-microcode` as
`UPDATE AVAILABLE`, apply via apt (NOT `just firmware-update`, which
only handles fwupd):

```sh
ansible <host> -m apt -a 'name=intel-microcode state=latest update_cache=yes' --become
# or amd64-microcode on AMD hosts
```

The apt postinst regenerates the initrd with the new microcode blob.
**Reboot is required** for the new microcode to load. Drain any k3s
workload first if the host carries Longhorn replicas or etcd CP VMs.

Verify after reboot:

```sh
ansible <host> -m shell -a 'journalctl -k -b | grep -i "microcode updated"' --become
# Intel:
ansible <host> -m shell -a 'grep microcode /proc/cpuinfo | head -1' --become
```

## Cadence recommendation

| Surface                  | Suggested rhythm                                 |
| ------------------------ | ------------------------------------------------ |
| `just firmware-plan`     | Monthly (catches LVFS firmware + microcode in one shot) |
| `just firmware-update X` | When `firmware-plan` reports something in the `FWUPD: UPDATES AVAILABLE` section |
| CPU microcode            | Same — applied via apt + reboot (see above)       |
| HP MP9 G2 BIOS           | Check HP support quarterly; flash on security CVEs |
| Samsung NVMe firmware    | Check Samsung's notifications quarterly — LVFS is unreliable here |
| Synology DSM             | Check monthly, patch critical DSMs same-week     |
| OPNsense                 | Apply business updates monthly                   |

## Troubleshooting

- **`fwupdmgr refresh` fails with a network error** — host can't reach
  `cdn.fwupd.org`. Check egress from that host (firewall, DNS,
  Tailscale exit-node misroute).
- **A device appears in `LVFS-CURRENT` but vendor publishes newer
  firmware** — LVFS may not have that vendor's catalogue at all (or
  may have stale metadata for it). `LVFS-CURRENT` only means "LVFS
  returned no update today", not "the vendor confirms current". Cross-
  check via the vendor's own update notifications for anything that
  matters (NVMe firmware in particular).
- **`apt-get update` fails in the plan** — the microcode candidate
  lookup needs a fresh apt index. If apt update fails, check DNS,
  network, and that the Proxmox / Debian mirrors are reachable from
  that host.
- **Update applied but `dmidecode` still shows the old version** — it's
  staged offline; reboot to apply (then re-check).
- **`intel-microcode` flagged as `MISSING`** — verify that
  `non-free-firmware` is in the apt sources; the microcode packages
  ship from that component on modern Debian.
- **A flash bricks a device** — for HP BIOS, the
  `Hewlett-Packard/BIOS/Current/` directory on the USB is the
  recovery path; HP business desktops boot from it automatically when
  the primary BIOS image fails verification.
