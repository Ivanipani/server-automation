#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL="https://pkg.opnsense.org/releases/26.1.2/OPNsense-26.1.2-vga-amd64.img.bz2"
IMAGE_BZ2="OPNsense-26.1.2-vga-amd64.img.bz2"
IMAGE="OPNsense-26.1.2-vga-amd64.img"

if [ -f "$IMAGE" ]; then
    echo "Image already exists: $IMAGE"
    exit 0
fi

echo "Downloading $IMAGE_BZ2..."
curl -L -o "$IMAGE_BZ2" "$IMAGE_URL"

echo "Extracting with bunzip2..."
bunzip2 "$IMAGE_BZ2"

echo "Done. Image ready: $IMAGE"
