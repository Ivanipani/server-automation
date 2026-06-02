#!/usr/bin/env bash
# Build a Proxmox VE auto-install ISO that runs the canonical
# image-baseline.sh as its --on-first-boot script.
#
# Bundles the rendered image-baseline.sh (ansible/tourmanager users,
# sshd hardening, apt-no-auto-upgrades, root-lock — the SAME script
# every other provisioning medium uses) via --on-first-boot; the
# installer wires it as a oneshot systemd service at first boot. There
# is no PVE-specific first-boot wrapper anymore: standalone nodes with
# static DHCP reservations don't need the old vmbr0 DHCP-flip /
# /etc/hosts fixup, so the baseline runs unmodified.
#
# This ISO path embeds the baseline (--on-first-boot, "from-iso"). The
# netboot path (bootserv01 PVE PXE) instead fetches the same baseline at
# install time via the answer.toml's `[first-boot] source = from-url`;
# the ISO path can't, since the foundation node is installed via ISO
# before bootserv01 exists.
#
# Usage:
#   ./build.sh <answer.toml>
#   FETCH_FROM=http ./build.sh <answer.toml>   # answer pulled via DHCP opt 250
#
# Output: ./output/proxmox-ve-<answer-stem>.iso
#
# Pre-conditions:
#   - proxmox-auto-install-assistant + xorriso + wget installed
#     (host-base puts them on every physical host; the operator
#      laptop needs them too)
#   - ansible + uv + repo's ansible-pass file present (the helper
#     playbook runs ansible to render the baseline script)

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <answer.toml>" >&2
  exit 2
fi

ANSWER_FILE="$(realpath "$1")"
ANSWER_STEM="$(basename "${ANSWER_FILE%.toml}")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_DIR/ansible"

OUTPUT_DIR="$SCRIPT_DIR/output"
BUILD_DIR="$SCRIPT_DIR/.build"
mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"

ISO_URL="${ISO_URL:-https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso}"
ISO_FILE="$BUILD_DIR/$(basename "$ISO_URL")"
PREPARED_ISO="$OUTPUT_DIR/proxmox-ve-${ANSWER_STEM}.iso"
FETCH_FROM="${FETCH_FROM:-iso}"

# ── 1. Tool check ───────────────────────────────────────────────
for cmd in proxmox-auto-install-assistant xorriso wget ansible-playbook; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is not installed." >&2
    echo "  For PVE tooling: apt install proxmox-auto-install-assistant xorriso wget" >&2
    echo "  For ansible: see repo's justfile (just install)" >&2
    exit 1
  fi
done

# ── 2. Render image-baseline.sh on the controller ───────────────
echo "Rendering image-baseline.sh via ansible..."
ansible-playbook \
  --vault-password-file "$ANSIBLE_DIR/ansible-pass" \
  "$ANSIBLE_DIR/playbooks/poochella/img/render-image-baseline-to-controller.yml"
BASELINE_SH="/var/tmp/poochella-image-baseline.sh"
[ -r "$BASELINE_SH" ] || { echo "Error: $BASELINE_SH not found after render"; exit 1; }

# Quick sanity check on the rendered baseline.
bash -n "$BASELINE_SH"

# ── 4. Download upstream PVE ISO if not cached ──────────────────
if [ ! -f "$ISO_FILE" ]; then
  echo "Downloading $ISO_URL ..."
  wget -O "$ISO_FILE" "$ISO_URL"
else
  echo "ISO already cached: $ISO_FILE"
fi

# ── 5. Validate the answer file ─────────────────────────────────
proxmox-auto-install-assistant validate-answer "$ANSWER_FILE"

# ── 6. Prepare the bundled ISO ──────────────────────────────────
echo "Bundling ISO -> $PREPARED_ISO"
if [ "$FETCH_FROM" = "iso" ]; then
  proxmox-auto-install-assistant prepare-iso "$ISO_FILE" \
    --fetch-from iso \
    --answer-file "$ANSWER_FILE" \
    --on-first-boot "$BASELINE_SH" \
    --output "$PREPARED_ISO"
else
  proxmox-auto-install-assistant prepare-iso "$ISO_FILE" \
    --fetch-from http \
    --on-first-boot "$BASELINE_SH" \
    --output "$PREPARED_ISO"
fi

# ── 7. Clean up the rendered baseline (contains vault hash) ─────
rm -f "$BASELINE_SH"

echo
echo "Built: $PREPARED_ISO"
