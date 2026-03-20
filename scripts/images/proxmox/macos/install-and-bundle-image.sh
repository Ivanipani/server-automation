#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
ISO_FILE="proxmox-ve_9.1-1.iso"
ANSWER_FILE="${SCRIPT_DIR}/../answer.toml"
PREPARED_ISO="proxmox-ve_9.1-1-autoinstall.iso"
DOCKER_IMAGE="proxmox-iso-builder"

# Download ISO if not already present
if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading Proxmox VE ISO..."
    wget "$ISO_URL"
else
    echo "ISO already downloaded: $ISO_FILE"
fi

# Build the helper image
echo "Building $DOCKER_IMAGE image..."
docker build -q -t "$DOCKER_IMAGE" "$SCRIPT_DIR"

# Prepare ISO with answer file
if [ ! -f "$PREPARED_ISO" ] || [ "$ANSWER_FILE" -nt "$PREPARED_ISO" ] || [ "$ISO_FILE" -nt "$PREPARED_ISO" ]; then
    echo "Validating answer file..."
    docker run --rm \
        -v "${ANSWER_FILE}:/work/answer.toml:ro" \
        "$DOCKER_IMAGE" validate-answer /work/answer.toml

    echo "Bundling answer file into ISO..."
    cp "$ISO_FILE" "$PREPARED_ISO"

    docker run --rm \
        -v "${PWD}/${PREPARED_ISO}:/work/target.iso" \
        -v "${ANSWER_FILE}:/work/answer.toml:ro" \
        "$DOCKER_IMAGE" prepare-iso /work/target.iso --fetch-from iso --answer-file /work/answer.toml

    echo "Prepared ISO: $PREPARED_ISO"
else
    echo "Prepared ISO already up to date: $PREPARED_ISO"
fi
