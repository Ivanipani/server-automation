#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BURN_SCRIPT="${SCRIPT_DIR}/../burn-to-disc.sh"
IMAGE="OPNsense-26.1.2-vga-amd64.img"

exec "$BURN_SCRIPT" "$IMAGE" ${1:+"$1"}
