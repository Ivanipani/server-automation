# Debian 13 baremetal unattended-install images

Builds per-host bootable USB images that install Debian 13 (Trixie) on a
specified baremetal host with **zero interaction**: plug in, boot, walk
away, come back to a Debian box that already trusts the fleet's `ansible`
user. Pairs with the kubernetes-native direction (baremetal k3s or
baremetal Proxmox + KubeVirt) without removing the existing Proxmox
auto-install path in `img/proxmox/`.

## Why this layout

| Layer                          | Where it lives                       | Owns                                         |
| ------------------------------ | ------------------------------------ | -------------------------------------------- |
| Upstream Debian netinst ISO    | `.cache/` (pinned URL + SHA512)      | the kernel, initrd, bootloader, package set  |
| Per-host preseed + boot overlay| `templates/*.j2` rendered to a workdir | hostname, install disk, tourmanager pw, ansible key |
| ISO repack (xorriso, in-place) | `build.sh`                           | preserving UEFI+BIOS hybrid boot             |
| Inventory (single source)      | `ansible/inventory.yaml`             | every value the preseed needs                |

The preseed is **embedded in the ISO** (loaded via
`preseed/file=/cdrom/preseed.cfg`) so the install needs nothing from the
network at boot time except DHCP — the same DHCP reservation OPNsense
already issues for the host's MAC. No PXE server, no HTTP preseed host.

## Prerequisites

1. **xorriso** on the build host (the laptop):
   - macOS: `brew install xorriso`
   - Linux: `apt install xorriso`
2. **ansible-core** + the project's collections — `just install` if you
   haven't already; `just check` to verify.
3. **The bootstrap SSH key** at `~/.ssh/ansible.pub`. This is the same key
   the existing Packer/Ansible flows install on every other box.
4. **The `tourmanager` break-glass password in the vault**. Add it once:
   ```
   just secret-encrypt vault_tourmanager_user_pass
   ```
   The indirection (`tourmanager_user_pass` → `vault_tourmanager_user_pass`)
   is already wired in `ansible/group_vars/all/vars.yml`. Same secret the
   `host-base` role uses to reconcile `tourmanager` on every physical host.
   Root is locked at install time — there is no `baremetal_root_password`
   any more; `tourmanager` is the single break-glass for every Debian box.

## Usage

```
just baremetal-iso pve-home-01
```

Produces `img/debian/output/debian-13-pve-home-01.iso` (+ `.sha256`).

Flash it (existing helper handles both Linux and macOS):

```
img/burn-to-disc.sh img/debian/output/debian-13-pve-home-01.iso disk4   # macOS
img/burn-to-disc.sh img/debian/output/debian-13-pve-home-01.iso sdb     # Linux
```

Boot the target from the USB. The default boot entry (`Auto-install
Debian 13 (<host>)`) selects itself after a 3-second timeout. The
installer's `preseed/early_command` walks `lsblk` and resolves the
install target by matching the `hw: {model, serial}` block on the
inventory's `storage.disks` entry marked `select: boot` — **no other
disk is touched**, leaving the data drives intact for the `host-disks`
role to carve post-install.

When the host comes back up, it'll DHCP onto its reserved IP, accept
SSH from `ansible@<host>.lan` using `~/.ssh/ansible`, and is ready for
the existing Ansible playbooks. `just ssh-refresh` will re-seed
`known_hosts` (the post-install host key is new).

## What you get on first boot

- `ansible` user in `sudo` + the canonical pubkey in
  `~/.ssh/authorized_keys` + `NOPASSWD: ALL` in `/etc/sudoers.d/ansible`
- `tourmanager` user in `sudo` with the vault password + `NOPASSWD: ALL`
  in `/etc/sudoers.d/tourmanager` — fleet-wide break-glass (console always
  works; SSH password-auth for `tourmanager` only, both before and after
  the `ssh-hardening` role's `Match User` block lands)
- `root` is **LOCKED** (no password, `PermitRootLogin no` already in
  `/etc/ssh/sshd_config.d/00-no-root.conf` from first boot). `sudo` from
  `ansible` / `tourmanager` is the only path to root.
- Whole-disk LVM on the install disk under VG `system`
- `openssh-server`, `python3`, `sudo`, `curl`, `ca-certificates`, `gnupg`
- Unattended upgrades disabled (matches `roles/apt-no-auto-upgrades`)
- DHCP networking — the static IP comes from the OPNsense reservation

## Co-existence with the Proxmox path

Nothing here removes `img/proxmox/`. Both ISOs target the same hardware;
flash whichever you want for the OS you want on that host. Inventory still
lists each box under `pve_standalone`; the boot disk is identified by the
`storage.disks[?select == 'boot'].hw.{model, serial}` pin (the same pin
the bootserv netboot preseed uses), and the existing `pve-home-XX.toml`
for the Proxmox auto-installer is untouched.

## Adding a third baremetal host

1. Add the host to `ansible/inventory.yaml` with `mac_address` and a
   `storage.disks` block whose boot entry is marked `select: boot` with
   `hw: { model, serial }` (`just disk-plan` after a live boot from a
   rescue medium prints model + serial per disk).
2. Add its MAC to the OPNsense dnsmasq reservation (`just do-router-dhcp`).
3. `just baremetal-iso <new-host>`.

## Refreshing the pinned upstream ISO

Bump `DEBIAN_ISO_URL` **and** `DEBIAN_ISO_SHA512` together in
`build.sh`. The script refuses to proceed on mismatch. SHA512 is published
alongside the ISO at
`https://cdimage.debian.org/cdimage/release/<v>/amd64/iso-cd/SHA512SUMS`.

## Troubleshooting

- **`vault_tourmanager_user_pass missing from group_vars/all/vault.yml`** —
  you haven't added the vault entry yet. Run
  `just secret-encrypt vault_tourmanager_user_pass`.
- **`Missing dependency: xorriso`** — install per Prerequisites above.
- **ISO boots but drops to a manual prompt** — the boot menu has a
  `Rescue: drop to manual installer` entry; if the *Auto-install* entry
  is doing this, the preseed is probably not at `/cdrom/preseed.cfg`.
  Check that `build.sh`'s `xorriso -map` step printed no error and
  inspect the ISO with `xorriso -indev <iso> -find /preseed.cfg`.
- **Wrong disk wiped** — the install target is the disk whose live
  `lsblk` model + serial match the inventory's `storage.disks`
  boot entry `hw:` pin. `just disk-plan` (or `lsblk -do PATH,MODEL,SERIAL`
  from a rescue boot) prints what each physical disk reports; cross-check
  the inventory pin against the actual hardware before flashing. The
  preseed `early_command` echoes the resolved `/dev/...` path before
  partitioning, and HARD-FAILS (sleeps 60s, exits 1) if no disk matches.
