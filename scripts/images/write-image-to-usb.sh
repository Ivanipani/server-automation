#!/usr/bin/env bash
set -euo pipefail

# Must be run from a Linux host

if [ $# -ne 2 ]; then
    echo "Usage: $0 <image-path> <device>"
    echo ""
    echo "Writes a disk image (ISO, img, etc.) to a USB drive."
    echo ""
    echo "Example: $0 /path/to/image.iso sdb"
    echo ""
    echo "----- Disks on [$(hostname)] -----"
    lsblk -d -o NAME,SIZE,MODEL,TRAN
    exit 127
fi

IMAGE="$1"
DEVICE="/dev/$2"

# Verify the image exists
if [ ! -f "$IMAGE" ]; then
    echo "Error: image not found: $IMAGE"
    exit 1
fi

# Verify the device exists
if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device."
    exit 1
fi

echo "WARNING: This will erase ALL data on $DEVICE"
echo ""
echo "Image:  $IMAGE ($(du -h "$IMAGE" | cut -f1))"
echo "Target: $DEVICE"
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

echo "Writing $IMAGE to $DEVICE (this may take several minutes)..."
dd if="$IMAGE" of="$DEVICE" bs=4M status=progress oflag=sync

echo "Done. $DEVICE is ready."
