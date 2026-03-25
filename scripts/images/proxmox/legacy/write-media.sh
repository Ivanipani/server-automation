#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BURN_SCRIPT="${SCRIPT_DIR}/../burn-to-disc.sh"
PREPARED_ISO="proxmox-ve_9.1-1-autoinstall.iso"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <device>"
    echo ""
    echo "Creates a bootable Proxmox VE USB drive with automated installation."
    echo "Bundles answer.toml into the ISO for unattended install."
    echo ""
    echo "Example (Linux): $0 sdb"
    echo "Example (macOS): $0 disk4"
    echo ""
    exec "$BURN_SCRIPT" 2>/dev/null || true
    exit 127
fi

if [ ! -f "$PREPARED_ISO" ]; then
    echo "Error: prepared ISO not found: $PREPARED_ISO"
    echo "Run install-and-bundle-image.sh first."
    exit 1
fi

exec "$BURN_SCRIPT" "$PREPARED_ISO" "$1"
