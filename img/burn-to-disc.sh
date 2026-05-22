#!/usr/bin/env bash
set -euo pipefail

OS="$(uname -s)"

list_disks() {
    case "$OS" in
        Linux)  lsblk -d -o NAME,SIZE,MODEL,TRAN ;;
        Darwin) diskutil list ;;
        *)      echo "Unsupported OS: $OS"; exit 1 ;;
    esac
}

show_device_info() {
    local device="$1"
    case "$OS" in
        Linux)  lsblk "$device" -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT ;;
        Darwin) diskutil info "$device" | grep -E 'Device|Total Size|Media Name|Protocol|Mount Point' ;;
    esac
}

unmount_device() {
    local device="$1"
    case "$OS" in
        Linux)
            for part in "${device}"*; do
                if mountpoint -q "$part" 2>/dev/null || grep -q "$part" /proc/mounts 2>/dev/null; then
                    echo "Unmounting $part..."
                    umount "$part"
                fi
            done
            ;;
        Darwin)
            echo "Unmounting all volumes on $device..."
            diskutil unmountDisk "$device" 2>/dev/null || true
            ;;
    esac
}

write_image() {
    local image="$1" device="$2"
    case "$OS" in
        Linux)
            dd if="$image" of="$device" bs=4M status=progress oflag=sync
            ;;
        Darwin)
            # Use raw disk device for much faster writes on macOS
            local raw_device="${device/disk/rdisk}"
            dd if="$image" of="$raw_device" bs=4m status=progress
            ;;
    esac
}

if [ $# -ne 2 ]; then
    echo "Usage: $0 <image-path> <device>"
    echo ""
    echo "Writes a disk image (ISO, img, etc.) to a USB drive."
    echo ""
    echo "Example (Linux): $0 /path/to/image.iso sdb"
    echo "Example (macOS): $0 /path/to/image.iso disk4"
    echo ""
    echo "----- Disks on [$(hostname)] -----"
    list_disks
    exit 127
fi

IMAGE="$1"
DEVICE="/dev/$2"

if [ ! -f "$IMAGE" ]; then
    echo "Error: image not found: $IMAGE"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device."
    exit 1
fi

echo "WARNING: This will erase ALL data on $DEVICE"
echo ""
echo "Image:  $IMAGE ($(du -h "$IMAGE" | cut -f1))"
echo "Target: $DEVICE"
echo ""
show_device_info "$DEVICE"
echo ""
read -rp "Continue? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 1
fi

unmount_device "$DEVICE"

echo "Writing $IMAGE to $DEVICE (this may take several minutes)..."
write_image "$IMAGE" "$DEVICE"

echo "Done. $DEVICE is ready."
