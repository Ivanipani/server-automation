# Hardware-probe live USB (`img/live`)

A bootable Debian 13 **live** USB that you plug into a *bare* machine — one with
no OS and no `inventory.yaml` entry yet — to read its real hardware and emit a
paste-ready inventory fragment. It is the pre-install counterpart to:

- `img/debian/` — *installs* a host from a **known** inventory entry.
- `ansible/roles/host-disks/tasks/discover.yml` (`just disk-plan`) — inspects an
  **already-booted, already-in-inventory** host over SSH.

This image needs neither: it runs locally on the bare box before any install.

## What it does

Boot the stick and it auto-runs `poochella-probe`, which prints a YAML fragment
for `ansible/inventory.yaml` containing:

- a **host hint** (DMI vendor / product / chassis serial) to help you name it,
- every **physical NIC** as a `mac_addresses` entry (with name / driver / link),
- every **fixed disk** (the live USB itself excluded) as a `storage.disks`
  candidate with a stable selector — `{model, serial}` plus a `{min_size_gib,
  rotational}` alternative — and an inline note showing how to promote one disk
  to `select: boot` + `hw: {model, serial}` (the marker `roles/bootserv` keys on
  to render the netboot preseed). `wipe: force` is pre-annotated on any disk that
  already carries foreign signatures.

It is strictly read-only: sysfs + `lsblk` + a non-destructive `wipefs -n` scan.
Nothing is partitioned or wiped.

The disk-attribute collection mirrors `discover.yml` exactly, so the selectors
it emits resolve against the same `host-disks` logic later.

## Build

```sh
just build-live          # or: img/live/build.sh
```

Downloads the pinned `debian-live-13.5.0-amd64-standard.iso` into `.cache/`
(SHA512-verified), overlays the probe + a `live-config` auto-run hook + minimal
boot menus via `xorriso`, and writes `output/debian-13-probe.iso` (+ `.sha256`).
Only `xorriso`, `curl`, `shasum` are required on the build host — no ansible,
no vault, no root.

To refresh the upstream image, bump `LIVE_ISO_URL` + `LIVE_ISO_SHA512` together
in `build.sh` (hash from the `SHA512SUMS` file next to the ISO on the mirror).

## Flash + boot

```sh
just flash-live <device>     # builds if missing, then dd's to /dev/<device>
# or: img/burn-to-disc.sh img/live/output/debian-13-probe.iso <device>
```

Boot the target from the USB (UEFI or BIOS; the ISO is hybrid). The default menu
entry passes `live-config.hooks=medium`, which runs the baked hook: it enables
root autologin on tty1, runs the probe, and starts a tiny HTTP server.

## Retrieve the fragment

Two ways, both shown on the console when the probe finishes:

- **Console** — read the printed YAML directly off tty1.
- **HTTP** — from your laptop, pull the saved copy (no SSH, no transcription):

  ```sh
  curl http://<dhcp-ip>:8000/inventory-fragment.yaml
  ```

  The probe prints the exact `curl` line with the host's DHCP IP filled in. The
  fragment also lives at `/run/poochella/inventory-fragment.yaml` on the box.

Re-run any time with `poochella-probe`.

> The standard live image has no `openssh-server`, so retrieval is console + the
> python3 HTTP server (python3 ships in the image). No internet is needed at
> probe time — the HTTP path works on an isolated LAN.

## Fold into inventory

1. Paste the fragment under the right group in `ansible/inventory.yaml`.
2. Fill every `<REPLACE...>`: hostname, `ip_address`, and unique partition
   `label`s. Pick exactly one disk as `select: boot` + `hw:` and classify the
   rest (worker → direct `mount:` ext4; hypervisor → `pve_storage: vms`).
3. After the host is actually installed, `just disk-plan --limit <host>` should
   report PRESENT for the declared partlabels — confirming the selectors match.

## Fallback

If the boot menu ever drifts (e.g. an upstream point release reshuffles the
boot configs and the overlay doesn't take), you can trigger the probe manually
by adding `live-config.hooks=medium` to the kernel command line at the boot
prompt — or just log in and run `bash /run/live/medium/poochella/probe.sh`.
