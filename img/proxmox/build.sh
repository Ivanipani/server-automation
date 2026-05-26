#!/usr/bin/env bash
# Build a Proxmox VE auto-install ISO that runs the canonical
# image-baseline.sh as its --on-first-boot script.
#
# Concatenates img/proxmox/first-boot.sh (PVE-specific bits: vmbr0
# DHCP flip, /etc/hosts oneshot for pve-cluster identity) with the
# rendered image-baseline.sh (ansible/tourmanager users, sshd
# hardening, apt-no-auto-upgrades, root-lock — same script every
# other provisioning medium uses). proxmox-auto-install-assistant
# bundles the combined script via --on-first-boot; the installer
# wires it as a oneshot systemd service at first boot.
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
COMBINED_FIRSTBOOT="$BUILD_DIR/first-boot-combined.sh"
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

# ── 3. Concatenate first-boot.sh + image-baseline.sh ────────────
# Order matters: PVE-specific networking fixup FIRST (the baseline
# script can then validate sshd config; sshd is installed by the
# PVE installer before first-boot fires).
echo "Building combined first-boot script: $COMBINED_FIRSTBOOT"
{
  cat "$SCRIPT_DIR/first-boot.sh"
  echo ""
  echo "# ── Canonical image-baseline (group_vars/all/image-baseline.yml) ──"
  # Skip the shebang on the second script — the outer script's #!/bin/sh
  # is the one that runs. Strip line 1.
  tail -n +2 "$BASELINE_SH"
} > "$COMBINED_FIRSTBOOT"
chmod 0755 "$COMBINED_FIRSTBOOT"

# Quick sanity check
bash -n "$COMBINED_FIRSTBOOT"

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
    --on-first-boot "$COMBINED_FIRSTBOOT" \
    --output "$PREPARED_ISO"
else
  proxmox-auto-install-assistant prepare-iso "$ISO_FILE" \
    --fetch-from http \
    --on-first-boot "$COMBINED_FIRSTBOOT" \
    --output "$PREPARED_ISO"
fi

# ── 7. Clean up the rendered baseline (contains vault hash) ─────
rm -f "$BASELINE_SH"

echo
echo "Built: $PREPARED_ISO"
