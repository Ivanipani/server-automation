#!/usr/bin/env bash
set -euo pipefail

# Must be run from a Linux host

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARED_ISO="proxmox-ve_9.1-1-autoinstall.iso"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <device>"
    echo ""
    echo "Creates a bootable Proxmox VE USB drive with automated installation."
    echo "Bundles answer.toml into the ISO for unattended install."
    echo ""
    echo "Example: $0 sdb    # writes to /dev/sdb"
    echo ""
    echo "----- Disks on [$(hostname)] -----"
    lsblk -d -o NAME,SIZE,MODEL,TRAN
    exit 127
fi

DEVICE="/dev/$1"

# Verify the device exists
if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device."
    exit 1
fi

# Verify prepared ISO exists
if [ ! -f "$PREPARED_ISO" ]; then
    echo "Error: prepared ISO not found: $PREPARED_ISO"
    echo "Run install-and-bundle-image.sh first."
    exit 1
fi

echo "WARNING: This will erase ALL data on $DEVICE"
echo ""
lsblk "$DEVICE" -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
echo ""
read -rp "Continue? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 1
fi

# Unmount any mounted partitions
for part in "${DEVICE}"*; do
    if mountpoint -q "$part" 2>/dev/null || grep -q "$part" /proc/mounts 2>/dev/null; then
        echo "Unmounting $part..."
        umount "$part"
    fi
done

echo "Writing ISO to $DEVICE (this may take several minutes)..."
dd if="$PREPARED_ISO" of="$DEVICE" bs=4M status=progress oflag=sync

echo "Done. Bootable Proxmox USB with automated installation is ready."
