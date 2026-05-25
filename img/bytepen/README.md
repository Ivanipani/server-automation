# bytepen

Disk-prep CLI for flashing images, partitioning, formatting, and wiping removable
media. Linux + macOS. Hybrid implementation: shells out to `lsblk`/`diskutil`/`sgdisk`
for OS-specific bits; pure-Rust write loop with a real progress bar.

**Status: alpha.** Ships alongside the existing `img/burn-to-disc.sh` flow — for
daily flashing, the bash script is still the recommended path until bytepen is
exercised on a few real disks.

## Build

```sh
cd img/bytepen
cargo build --release
# binary lands at target/release/bytepen
```

No cross-compilation: build on the platform you'll run it on.

## Usage

```sh
bytepen list                                   # candidate disks
bytepen info /dev/disk4                        # show device details
sudo bytepen flash image.iso /dev/disk4        # dd-equivalent, with progress bar
sudo bytepen wipe /dev/disk4                   # zero first/last 10 MiB
sudo bytepen wipe /dev/disk4 --full            # zero the entire device
sudo bytepen partition /dev/disk4 \
    --table gpt --layout '1:0:+1G:ef00,2:0:0:8300'
sudo bytepen format /dev/disk6 --fs exfat --label MYUSB     # full erase + format
```

### `format` is a full erase

`bytepen format <disk> --fs X` wipes ALL existing partitions and filesystems on the
target disk and creates a fresh filesystem. It only accepts whole disks (e.g.
`/dev/disk6`, `/dev/sdb`, `/dev/nvme0n1`) — slices like `/dev/disk6s1` are rejected.

- **Linux:** `wipefs --all --force` → `sgdisk --zap-all` → `mkfs.<fs>` directly on
  the disk (superfloppy layout, no partition table).
- **macOS:** `diskutil eraseDisk <fs> <name> <disk>` (fresh GPT + one volume,
  formatted).

All destructive subcommands prompt for confirmation; pass `--yes` to skip.

### Partition layout syntax

- **Linux** (sgdisk): comma-separated `N:start:end:typecode` entries. Forwarded
  verbatim to `sgdisk --new=N:start:end --typecode=N:typecode`. See `sgdisk(8)`.
- **macOS** (diskutil): space-separated `Format Name Size` triples. Forwarded
  verbatim as additional arguments to `diskutil partitionDisk`. See
  `diskutil partitionDisk` in `man diskutil`.

## Why not just bash + dd

- Real progress bar with bytes/sec and ETA (indicatif), not dd's stop-the-world
  signal-based status line.
- One binary covers flash + partition + format + wipe with consistent prompts and
  device validation, instead of one bash script per op.
- Catches "wrong device" / "image truncated" earlier with structured errors.

## What this does NOT do

- Verify-write (read-back checksum). Coming in v2.
- Self-elevate via sudo. If you forget `sudo`, you get a clean error and a retry.
- Replace `img/burn-to-disc.sh`. The bash script remains the recommended path
  until bytepen has more mileage.
