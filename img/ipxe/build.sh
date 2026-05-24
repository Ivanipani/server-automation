#!/usr/bin/env bash
# Build the iPXE rescue/debug bootable image pair.
#
# Usage:  img/ipxe/build.sh
#
# Produces two artifacts in img/ipxe/output/:
#   ipxe-bios.iso   -- legacy-BIOS hybrid ISO (boots from optical and from
#                      USB via `dd`)
#   ipxe-uefi.iso   -- UEFI ISO with an EFI system partition (also
#                      USB-`dd`-able on UEFI machines)
#
# Both binaries embed a tiny script that DHCPs and drops to the iPXE
# shell. The point is a rescue stick that stays useful when the normal
# NIC-PXE → OPNsense → bootserv01 chain is broken — DHCP failure does not
# abort to firmware, it lands in the shell where the operator can
# `ifstat` / `ping` / `chain` by hand. To pick up the standard
# bootserv flow manually from the shell:
#
#     iPXE> chain http://bootserv01.lan/boot.ipxe
#
# Built natively on a Debian 13 / Proxmox VE 9 host (typically
# pve-home-01). Build deps must be installed once:
#
#     sudo apt install -y build-essential perl liblzma-dev mtools \
#         dosfstools xorriso isolinux syslinux-common
#
# None of the above conflict with PVE's apt hook (the blocklist is
# qemu-system-x86 / qemu-utils / ovmf / ansible-metapackage).
#
# References: https://ipxe.org/download  https://ipxe.org/embed

set -euo pipefail

# --- Pinned upstream ------------------------------------------------------
# iPXE ships no release cadence we can pin to; master is the de-facto
# stable branch. For reproducibility, copy the resolved SHA printed at
# the end of a successful build into IPXE_GIT_REF (env or this line).
readonly IPXE_GIT_URL="https://github.com/ipxe/ipxe.git"
readonly IPXE_GIT_REF="${IPXE_GIT_REF:-master}"

# --- Paths ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SRC_DIR="${CACHE_DIR}/ipxe"
EMBED_FILE="${CACHE_DIR}/embed.ipxe"
OUT_BIOS="${OUTPUT_DIR}/ipxe-bios.iso"
OUT_UEFI="${OUTPUT_DIR}/ipxe-uefi.iso"

# --- Dependency check -----------------------------------------------------
APT_LINE="sudo apt install -y build-essential perl liblzma-dev mtools dosfstools xorriso isolinux syslinux-common"

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing dependency: $1" >&2
        echo "Install all build deps:" >&2
        echo "  ${APT_LINE}" >&2
        exit 1
    fi
}
require git
require make
require gcc
require perl
require xorriso
require mcopy        # mtools, for UEFI FAT image
require mkfs.fat     # dosfstools, for UEFI FAT image
require shasum

# Isolinux ships its boot record as a data file rather than an executable,
# so `command -v` cannot find it. Check the canonical path the Debian
# isolinux package installs to.
if [ ! -f /usr/lib/ISOLINUX/isolinux.bin ]; then
    echo "Missing /usr/lib/ISOLINUX/isolinux.bin (Debian 'isolinux' package)" >&2
    echo "Install all build deps:" >&2
    echo "  ${APT_LINE}" >&2
    exit 1
fi

mkdir -p "${CACHE_DIR}" "${OUTPUT_DIR}"

# --- 1. Sync iPXE source --------------------------------------------------
# Full clone (not --depth 1) so an arbitrary commit SHA in IPXE_GIT_REF
# resolves. `git fetch` keeps re-runs current; the build itself is
# incremental thanks to the preserved object files in src/bin*.
if [ -d "${SRC_DIR}/.git" ]; then
    echo "[1/5] Fetching iPXE updates"
    git -C "${SRC_DIR}" fetch --quiet --tags origin
else
    echo "[1/5] Cloning ${IPXE_GIT_URL}"
    git clone --quiet "${IPXE_GIT_URL}" "${SRC_DIR}"
fi
git -C "${SRC_DIR}" checkout --quiet --detach "${IPXE_GIT_REF}"
RESOLVED_SHA="$(git -C "${SRC_DIR}" rev-parse HEAD)"

# --- 2. Render embedded script -------------------------------------------
# Trailing `shell` is mandatory: an EMBED'd iPXE binary exits to firmware
# once the script completes, so without it a DHCP success would bounce
# back to the boot menu. `dhcp || ...` keeps the shell reachable on DHCP
# failure (which is the rescue case this stick exists for).
echo "[2/5] Rendering embedded script -> ${EMBED_FILE}"
cat > "${EMBED_FILE}" <<'EOF'
#!ipxe
echo
echo iPXE ${version} on ${net0/mac} (${manufacturer} ${product})
echo
dhcp || echo DHCP failed; continuing without it.
shell
EOF

# --- 3. Drop config overlay ----------------------------------------------
# iPXE's stock build omits most diagnostic commands to keep ROM size
# down; for an ISO/USB target the size budget is irrelevant, so enable
# the kit an operator actually wants in a rescue shell. See
# https://ipxe.org/buildcfg — the config/local/ overlay is the
# documented extension point.
echo "[3/5] Writing config/local/general.h"
mkdir -p "${SRC_DIR}/src/config/local"
cat > "${SRC_DIR}/src/config/local/general.h" <<'EOF'
/* Rescue-stick overlay. Rewritten by img/ipxe/build.sh on every run. */
#define PING_CMD
#define NSLOOKUP_CMD
#define IPSTAT_CMD
#define TIME_CMD
#define DIGEST_CMD
#define VLAN_CMD
#define LOTEST_CMD
#define NTP_CMD
#define REBOOT_CMD
#define POWEROFF_CMD
#define IMAGE_TRUST_CMD
#define DOWNLOAD_PROTO_HTTPS
EOF

# --- 4. Build the two ISOs -----------------------------------------------
# Separate output trees (bin/ vs bin-x86_64-efi/) → two make
# invocations. The Makefile keys the platform off the bin-<platform>
# prefix; mixing both in a single line is not supported.
echo "[4/5] Building iPXE ${IPXE_GIT_REF} @ ${RESOLVED_SHA:0:12}"
(
    cd "${SRC_DIR}/src"
    make -j"$(nproc)" bin/ipxe.iso              EMBED="${EMBED_FILE}"
    make -j"$(nproc)" bin-x86_64-efi/ipxe.iso   EMBED="${EMBED_FILE}"
)
cp "${SRC_DIR}/src/bin/ipxe.iso"            "${OUT_BIOS}"
cp "${SRC_DIR}/src/bin-x86_64-efi/ipxe.iso" "${OUT_UEFI}"

# --- 5. Hash artifacts ---------------------------------------------------
echo "[5/5] Hashing artifacts"
(
    cd "${OUTPUT_DIR}"
    shasum -a 256 "$(basename "${OUT_BIOS}")" > "$(basename "${OUT_BIOS}").sha256"
    shasum -a 256 "$(basename "${OUT_UEFI}")" > "$(basename "${OUT_UEFI}").sha256"
)

echo ""
echo "Built (iPXE @ ${RESOLVED_SHA}):"
printf '  %-40s %s\n' "${OUT_BIOS}" "$(shasum -a 256 "${OUT_BIOS}" | awk '{print $1}')"
printf '  %-40s %s\n' "${OUT_UEFI}" "$(shasum -a 256 "${OUT_UEFI}" | awk '{print $1}')"
echo ""
echo "Flash to USB:"
echo "  img/burn-to-disc.sh '${OUT_BIOS}' <device>   # legacy BIOS host"
echo "  img/burn-to-disc.sh '${OUT_UEFI}' <device>   # UEFI host"
