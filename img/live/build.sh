#!/usr/bin/env bash
# Build the poochella hardware-probe live USB image.
#
# Usage:  img/live/build.sh
#
# Flow:
#   1. Download the pinned upstream Debian 13 live-standard ISO into .cache/
#      (skip if the cached file already matches the pinned SHA512).
#   2. Author two minimal boot menus (UEFI grub + BIOS isolinux) whose single
#      default entry boots `boot=live` with `live-config.hooks=medium`, so the
#      baked probe hook auto-runs. They reference the stable /live/vmlinuz and
#      /live/initrd.img symlinks, so no kernel-version string is hardcoded.
#   3. Use xorriso in indev/outdev mode to overlay those boot menus plus the
#      probe + live-config hook onto a copy of the source ISO, preserving the
#      El Torito MBR + EFI boot record so the result stays a true hybrid
#      (UEFI + BIOS) ISO that img/burn-to-disc.sh can write to USB unchanged.
#   4. sha256sum the artifact next to it.
#
# The repack step is the only piece that needs `xorriso` on the build host
# (brew install xorriso on macOS; apt install xorriso on Debian). Nothing runs
# as root, nothing touches target hardware — this is pure file assembly.
#
# This image is host-agnostic: unlike img/debian/build.sh there is no per-host
# rendering and no ansible/vault dependency. Boot it on any bare machine; it
# prints an inventory fragment to the console and serves it over HTTP.

set -euo pipefail

# --- Pinned upstream artifact ---------------------------------------------
# Bump LIVE_ISO_URL + LIVE_ISO_SHA512 together to refresh. The SHA is from the
# SHA512SUMS file alongside the ISO on the same mirror path. Pinning avoids
# "today's build works, tomorrow's silently regresses".
readonly LIVE_ISO_URL="https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.5.0-amd64-standard.iso"
readonly LIVE_ISO_SHA512="65e86d60a6a70981e9730de5e26c7eab6ab47eb8a7ed1493fe83d58394021500c81b1f64f05ca59419687ee13e7028eb48f1f69150953d6240f1b0d745c56e1e"

# --- Paths ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
OUTPUT_DIR="${SCRIPT_DIR}/output"
WORKDIR="${CACHE_DIR}/work"
SRC_ISO="${CACHE_DIR}/$(basename "${LIVE_ISO_URL}")"
OUTPUT_ISO="${OUTPUT_DIR}/debian-13-probe.iso"

# --- Dependency check -----------------------------------------------------
require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing dependency: $1" >&2
        echo "$2" >&2
        exit 1
    fi
}
require xorriso "Install: brew install xorriso (macOS) / apt install xorriso (Linux)"
require curl "Install: it ships with macOS / Linux base"
require shasum "Install: it ships with macOS / Linux coreutils"

# --- 1. Cache the source ISO ---------------------------------------------
mkdir -p "${CACHE_DIR}" "${OUTPUT_DIR}"

sha512_matches() {
    local file="$1" expected="$2" got
    [ -f "${file}" ] || return 1
    got="$(shasum -a 512 "${file}" | awk '{print $1}')"
    [ "${got}" = "${expected}" ]
}

if sha512_matches "${SRC_ISO}" "${LIVE_ISO_SHA512}"; then
    echo "[1/4] Source ISO cache hit: ${SRC_ISO}"
else
    echo "[1/4] Downloading ${LIVE_ISO_URL}"
    curl --fail --location --output "${SRC_ISO}.partial" "${LIVE_ISO_URL}"
    mv "${SRC_ISO}.partial" "${SRC_ISO}"
    if ! sha512_matches "${SRC_ISO}" "${LIVE_ISO_SHA512}"; then
        echo "ERROR: SHA512 mismatch on ${SRC_ISO}" >&2
        echo "  expected: ${LIVE_ISO_SHA512}" >&2
        echo "  got:      $(shasum -a 512 "${SRC_ISO}" | awk '{print $1}')" >&2
        echo "If the upstream release moved, bump LIVE_ISO_URL + LIVE_ISO_SHA512 in this script." >&2
        exit 1
    fi
fi

# --- 2. Author the boot menus --------------------------------------------
# Both reference the version-independent /live/vmlinuz + /live/initrd.img
# symlinks and add `live-config.hooks=medium` so the probe hook auto-runs.
echo "[2/4] Authoring boot menus + staging overlay files"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"

cat > "${WORKDIR}/grub.cfg" <<'EOF'
set default=0
set timeout=3

menuentry "Poochella hardware probe (Debian 13 live)" {
    linux  /live/vmlinuz boot=live components live-config.hooks=medium quiet
    initrd /live/initrd.img
}
EOF

cat > "${WORKDIR}/isolinux.cfg" <<'EOF'
default probe
prompt 0
timeout 30
say Poochella hardware probe -- booting Debian 13 live...

label probe
  kernel /live/vmlinuz
  append initrd=/live/initrd.img boot=live components live-config.hooks=medium quiet
EOF

# --- 3. Repack ISO with xorriso ------------------------------------------
# `-boot_image any replay` re-derives the upstream's boot setup (El Torito +
# isohybrid MBR + GPT + APM) and RECOMPUTES the partition table for the new
# image size. We must NOT use `keep` here: the Debian live ISO is a GPT/APM
# hybrid, and `keep` preserves the original partition table byte-for-byte —
# its entries then point past the end of the re-sized image, which stricter
# xorriso builds (Linux) report as a SORRY event and exit 32 on. `replay`
# keeps the result hybrid-bootable without the stale pointers.
# `-pathspecs on` + `-map` add files at the target paths (replacing the two
# boot menus, adding the probe and the live-config hook).
#
# Files placed:
#   /boot/grub/grub.cfg            -- UEFI menu (replaced)
#   /isolinux/isolinux.cfg         -- BIOS menu (replaced)
#   /poochella/probe.sh            -- the emitter (hook copies it into place)
#   /live/config-hooks/probe-hook.sh -- live-config medium hook (auto-run)
echo "[3/4] Repacking ISO -> ${OUTPUT_ISO}"
rm -f "${OUTPUT_ISO}"

xorriso \
    -indev "${SRC_ISO}" \
    -outdev "${OUTPUT_ISO}" \
    -boot_image any replay \
    -volid "POOCHELLA_PROBE" \
    -pathspecs on \
    -map "${WORKDIR}/grub.cfg"          /boot/grub/grub.cfg \
    -map "${WORKDIR}/isolinux.cfg"      /isolinux/isolinux.cfg \
    -map "${SCRIPT_DIR}/probe.sh"       /poochella/probe.sh \
    -map "${SCRIPT_DIR}/probe-hook.sh"  /live/config-hooks/probe-hook.sh \
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
echo "  img/burn-to-disc.sh '${OUTPUT_ISO}' <device>   (or: just flash-live <device>)"
