#!/usr/bin/env bash
# Build a host-specific Debian 13 unattended-install USB image.
#
# Usage:  img/debian/build.sh <inventory-hostname>
#
# Flow:
#   1. Download the pinned upstream Debian 13 netinst ISO into .cache/
#      (skip if the cached file already matches the pinned SHA512).
#   2. Run img/debian/playbook.yml on localhost to render preseed.cfg,
#      grub.cfg, txt.cfg, and authorized_keys for <inventory-hostname>
#      into a per-host workdir under .cache/work/.
#   3. Use xorriso in indev/outdev mode to overlay those four files onto
#      a copy of the source ISO, preserving the El Torito MBR + EFI boot
#      record so the result remains a true hybrid (UEFI + BIOS) ISO that
#      `dd`/`img/burn-to-disc.sh` can write to USB unchanged.
#   4. sha256sum the artifact next to it.
#
# The repack step is the only piece that needs `xorriso` on the build host
# (brew install xorriso on macOS; apt install xorriso on Debian). Nothing
# runs as root, nothing touches the target hardware — this is pure file
# assembly. Boot the resulting ISO from USB on the target machine; the
# preseed handles the rest.

set -euo pipefail

# --- Pinned upstream artifact ---------------------------------------------
# Bump DEBIAN_ISO_URL + DEBIAN_ISO_SHA512 together to refresh. The SHA is
# taken from the SHA512SUMS file alongside the ISO on the same mirror path.
# Pinning avoids "today's build works, tomorrow's silently regresses".
readonly DEBIAN_ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.5.0-amd64-netinst.iso"
readonly DEBIAN_ISO_SHA512="b2be60c555e328b4fa5ebb2d0e5c7ee6bc3eb4250c4dcfd3f78b8d9aec596efdf9f14f10a898c280eb252d50bbac91ea0a2bba29736df0d4985d50d4c8d77519"

# --- Paths ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
CACHE_DIR="${SCRIPT_DIR}/.cache"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SRC_ISO="${CACHE_DIR}/$(basename "${DEBIAN_ISO_URL}")"

# --- Usage ----------------------------------------------------------------
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <inventory-hostname>" >&2
    echo "" >&2
    echo "Example: $0 pve-home-01" >&2
    exit 64
fi
readonly TARGET_HOST="$1"
readonly WORKDIR="${CACHE_DIR}/work/${TARGET_HOST}"
readonly OUTPUT_ISO="${OUTPUT_DIR}/debian-13-${TARGET_HOST}.iso"

# --- Dependency check -----------------------------------------------------
require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing dependency: $1" >&2
        echo "$2" >&2
        exit 1
    fi
}
require xorriso "Install: brew install xorriso (macOS) / apt install xorriso (Linux)"
require ansible-playbook "Install: just install (sets up ansible-core via uv)"
require curl "Install: it ships with macOS / Linux base"
require shasum "Install: it ships with macOS / Linux coreutils"

# --- 1. Cache the source ISO ---------------------------------------------
mkdir -p "${CACHE_DIR}" "${OUTPUT_DIR}"

sha512_matches() {
    local file="$1" expected="$2"
    [ -f "${file}" ] || return 1
    local got
    got="$(shasum -a 512 "${file}" | awk '{print $1}')"
    [ "${got}" = "${expected}" ]
}

if sha512_matches "${SRC_ISO}" "${DEBIAN_ISO_SHA512}"; then
    echo "[1/4] Source ISO cache hit: ${SRC_ISO}"
else
    echo "[1/4] Downloading ${DEBIAN_ISO_URL}"
    curl --fail --location --output "${SRC_ISO}.partial" "${DEBIAN_ISO_URL}"
    mv "${SRC_ISO}.partial" "${SRC_ISO}"
    if ! sha512_matches "${SRC_ISO}" "${DEBIAN_ISO_SHA512}"; then
        echo "ERROR: SHA512 mismatch on ${SRC_ISO}" >&2
        echo "  expected: ${DEBIAN_ISO_SHA512}" >&2
        echo "  got:      $(shasum -a 512 "${SRC_ISO}" | awk '{print $1}')" >&2
        echo "If the upstream release moved, bump DEBIAN_ISO_URL + DEBIAN_ISO_SHA512 in this script." >&2
        exit 1
    fi
fi

# --- 2. Render preseed + boot overlay via the Ansible playbook -----------
echo "[2/4] Rendering preseed + boot configs for ${TARGET_HOST}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"

# Run from ${ANSIBLE_DIR} so ansible.cfg + inventory + vault are auto-found
# (same pattern as `just run`). Vault file is the repo's `ansible-pass`.
(
    cd "${ANSIBLE_DIR}"
    ansible-playbook \
        --vault-password-file ansible-pass \
        --extra-vars "target_host=${TARGET_HOST}" \
        --extra-vars "workdir=${WORKDIR}" \
        "${SCRIPT_DIR}/playbook.yml"
)

for f in preseed.cfg grub.cfg txt.cfg authorized_keys; do
    [ -f "${WORKDIR}/${f}" ] || { echo "Renderer did not produce ${f}" >&2; exit 1; }
done

# --- 3. Repack ISO with xorriso ------------------------------------------
# `-boot_image any keep` preserves the upstream's El Torito catalog (MBR +
# EFI), so the result is still hybrid-bootable. `-map` adds files at the
# target paths; `-update` is unnecessary because we are writing to a fresh
# outdev. `-pathspecs on` enables the `target=source` shorthand in -map.
#
# Files placed:
#   /preseed.cfg          -- d-i loads via preseed/file=/cdrom/preseed.cfg
#   /authorized_keys      -- copied into /home/ansible/.ssh by late_command
#   /boot/grub/grub.cfg   -- UEFI auto-boot menu
#   /isolinux/txt.cfg     -- BIOS/isolinux auto-boot menu
#
# Volid is set to a distinctive label so the d-i `cdrom-detect` step
# matches the burned USB unambiguously even on machines with another
# Debian ISO mounted.
echo "[3/4] Repacking ISO -> ${OUTPUT_ISO}"
rm -f "${OUTPUT_ISO}"

xorriso \
    -indev "${SRC_ISO}" \
    -outdev "${OUTPUT_ISO}" \
    -boot_image any keep \
    -volid "DEBIAN_13_${TARGET_HOST}" \
    -pathspecs on \
    -map "${WORKDIR}/preseed.cfg"     /preseed.cfg \
    -map "${WORKDIR}/authorized_keys" /authorized_keys \
    -map "${WORKDIR}/grub.cfg"        /boot/grub/grub.cfg \
    -map "${WORKDIR}/txt.cfg"         /isolinux/txt.cfg \
    -commit

# --- 4. Checksum the artifact --------------------------------------------
echo "[4/4] Hashing ${OUTPUT_ISO}"
(
    cd "${OUTPUT_DIR}"
    shasum -a 256 "$(basename "${OUTPUT_ISO}")" > "$(basename "${OUTPUT_ISO}").sha256"
)

echo ""
echo "Built: ${OUTPUT_ISO}"
echo "       $(shasum -a 256 "${OUTPUT_ISO}" | awk '{print $1}')"
echo ""
echo "Flash to USB:"
echo "  img/burn-to-disc.sh '${OUTPUT_ISO}' <device>"
