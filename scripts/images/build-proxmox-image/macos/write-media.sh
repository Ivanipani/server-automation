#!/usr/bin/env bash
set -euo pipefail

# Must be run from a macos host

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
ISO_FILE="proxmox-ve_9.1-1.iso"
ANSWER_FILE="${SCRIPT_DIR}/../.claude/answer.toml"
PREPARED_ISO="proxmox-ve_9.1-1-autoinstall.iso"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <disk-number>"
    echo ""
    echo "Creates a bootable Proxmox VE USB drive with automated installation."
    echo "Bundles answer.toml into the ISO for unattended install."
    echo ""
    echo "Example: $0 4    # writes to /dev/disk4"
    echo ""
    echo "----- Disks on [$(hostname)] -----"
    diskutil list
    exit 127
fi

DISK_NUM="$1"
DISK="/dev/disk${DISK_NUM}"
RDISK="/dev/rdisk${DISK_NUM}"

# Verify the disk exists
if ! diskutil info "$DISK" > /dev/null 2>&1; then
    echo "Error: $DISK does not exist."
    exit 1
fi

# Verify answer file exists
if [ ! -f "$ANSWER_FILE" ]; then
    echo "Error: answer file not found at $ANSWER_FILE"
    exit 1
fi

echo "WARNING: This will erase ALL data on $DISK"
echo ""
diskutil info "$DISK"
echo ""
read -rp "Continue? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 1
fi

echo "Unmounting $DISK..."
diskutil unmountDisk "$DISK"

echo "Writing ISO to $RDISK (this may take several minutes)..."
sudo dd if="$PREPARED_ISO" of="$RDISK" bs=4M status=progress

echo "Ejecting $DISK..."
diskutil eject "$DISK"

echo "Done. Bootable Proxmox USB with automated installation is ready."
