#!/usr/bin/env bash
set -euo pipefail

# Must be run from a Linux host (e.g., the Proxmox server itself)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
ISO_FILE="proxmox-ve_9.1-1.iso"
ANSWER_FILE="${SCRIPT_DIR}/../answer.toml"
PREPARED_ISO="proxmox-ve_9.1_bundled.iso"
FETCH_FROM="${FETCH_FROM:-iso}"

# Ensure required tools are installed
for cmd in proxmox-auto-install-assistant xorriso wget; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "Error: '$cmd' is not installed."
        echo "Install with: apt install proxmox-auto-install-assistant xorriso wget"
        exit 1
    fi
done

# Download ISO if not already present
if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading Proxmox VE ISO..."
    wget "$ISO_URL"
else
    echo "ISO already downloaded: $ISO_FILE"
fi

if [ "$FETCH_FROM" = "iso" ]; then
    # Verify answer file exists
    if [ ! -f "$ANSWER_FILE" ]; then
        echo "Error: answer file not found at $ANSWER_FILE"
        exit 1
    fi

    echo "Validating answer file..."
    proxmox-auto-install-assistant validate-answer "$ANSWER_FILE"

    echo "Bundling answer file into ISO..."
    proxmox-auto-install-assistant prepare-iso "$ISO_FILE" \
        --fetch-from iso \
        --answer-file "$ANSWER_FILE" \
        --output "$PREPARED_ISO"
else
    echo "Preparing ISO to fetch answer via HTTP (DHCP option 250)..."
    proxmox-auto-install-assistant prepare-iso "$ISO_FILE" \
        --fetch-from http \
        --output "$PREPARED_ISO"
fi

