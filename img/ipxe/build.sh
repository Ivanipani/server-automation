#!/usr/bin/env bash
# Build the iPXE rescue/debug bootable image pair, OR fetch the stock
# upstream image with no local customizations.
#
# Usage:
#   img/ipxe/build.sh                # build customized iPXE (default)
#   img/ipxe/build.sh --vanilla      # fetch stock ipxe.org image (no build)
#
# DEFAULT (customized) build produces two artifacts in img/ipxe/output/:
#   ipxe-bios.iso   -- legacy-BIOS hybrid ISO (boots from optical and from
#                      USB via `dd`)
#   ipxe-uefi.iso   -- UEFI ISO with an EFI system partition (also
#                      USB-`dd`-able on UEFI machines)
# Both binaries embed our auto-chain script (see the embed section below)
# and a config overlay enabling extra diagnostic commands.
#
# `--vanilla` produces ONE artifact:
#   ipxe-vanilla.iso -- the stock hybrid ISO from https://boot.ipxe.org/
# No build, no embed, no overlay — useful as a sanity check when the
# customized image misbehaves on weird firmware. Stock iPXE's default
# autoboot DHCPs each NIC, identifies as user-class=iPXE, and chains
# whatever filename DHCP returns — so with our OPNsense `ipxe` tag rule
# already serving `http://bootserv01.lan/boot.ipxe`, vanilla iPXE
# auto-installs end-to-end with zero embed-script involvement.
#
# To pick up the standard bootserv flow manually from the shell on any
# variant (default or vanilla, if you end up in one):
#
#     iPXE> chain http://bootserv01.lan/boot.ipxe
#
# Customized builds run natively on a Debian 13 / Proxmox VE 9 host
# (typically pve-home-01). Build deps must be installed once:
#
#     sudo apt install -y build-essential perl liblzma-dev mtools \
#         dosfstools xorriso isolinux syslinux-common
#
# None of the above conflict with PVE's apt hook (the blocklist is
# qemu-system-x86 / qemu-utils / ovmf / ansible-metapackage).
# `--vanilla` only needs curl + shasum (both ship with the base OS).
#
# References: https://ipxe.org/download  https://ipxe.org/embed

set -euo pipefail

# --- Argument parsing -----------------------------------------------------
VANILLA=false
while [ $# -gt 0 ]; do
    case "$1" in
        --vanilla)
            VANILLA=true
            shift
            ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--vanilla]" >&2
            exit 64
            ;;
    esac
done

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
OUT_VANILLA="${OUTPUT_DIR}/ipxe-vanilla.iso"

mkdir -p "${OUTPUT_DIR}"

# --- Vanilla mode short-circuit ------------------------------------------
# Fetch the stock hybrid ISO from boot.ipxe.org, hash it, exit. This path
# deliberately avoids every customization (no embed script, no config
# overlay, no local build). It's the canonical "what does upstream do?"
# sanity check — useful when the customized build misbehaves on quirky
# firmware (USB keyboard not enumerating, embed script parsing issues,
# etc.). Upstream publishes only "latest master" — no version pinning
# available on the prebuilt artifact, so accept that this image floats
# with whatever ipxe.org built most recently.
if [ "${VANILLA}" = "true" ]; then
    require_vanilla() {
        if ! command -v "$1" >/dev/null 2>&1; then
            echo "Missing dependency: $1 (needed even for --vanilla)" >&2
            exit 1
        fi
    }
    require_vanilla curl
    require_vanilla shasum

    readonly IPXE_VANILLA_URL="https://boot.ipxe.org/ipxe.iso"
    echo "[1/2] Fetching stock iPXE ISO from ${IPXE_VANILLA_URL}"
    curl --fail --location --output "${OUT_VANILLA}.partial" "${IPXE_VANILLA_URL}"
    mv "${OUT_VANILLA}.partial" "${OUT_VANILLA}"

    echo "[2/2] Hashing"
    (
        cd "${OUTPUT_DIR}"
        shasum -a 256 "$(basename "${OUT_VANILLA}")" > "$(basename "${OUT_VANILLA}").sha256"
    )

    echo ""
    echo "Fetched stock iPXE (no customization):"
    printf '  %-40s %s\n' "${OUT_VANILLA}" "$(shasum -a 256 "${OUT_VANILLA}" | awk '{print $1}')"
    echo ""
    echo "Flash to USB (hybrid ISO — works on both BIOS and UEFI hosts):"
    echo "  img/burn-to-disc.sh '${OUT_VANILLA}' <device>"
    echo ""
    echo "Stock iPXE's autoboot DHCPs as user-class=iPXE and chains the"
    echo "filename it gets back, so OPNsense's existing ipxe-tag rule"
    echo "(serving http://bootserv01.lan/boot.ipxe) drives the install"
    echo "with zero embed-script involvement."
    exit 0
fi

# --- Dependency check (build path only) ----------------------------------
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
# Boot strategy:
#   1. DHCP. If it fails → drop to shell.
#   2. Chain http://bootserv01.lan/boot.ipxe (the standard fleet
#      dispatcher served by the bootserv01 LXC). If it succeeds, iPXE
#      hands off to that script and we boot a kernel+initrd from there
#      — no keyboard input required end-to-end.
#   3. If chain fails (server down, network broken, etc.) → drop to
#      shell so the operator can poke around. The shell is wrapped in
#      a `:shell_loop` so accidentally typing `exit` re-enters it
#      instead of falling through to iPXE's autoboot hunt for
#      `autoexec.ipxe` (which always fails for a USB rescue stick).
#
# Why fully-auto rather than always-shell:
# We learned the hard way that some UEFI firmware (e.g. ASUS boards
# with certain USB controllers) don't enumerate the USB keyboard for
# iPXE in time to interact with the shell — DHCP completes, the
# `iPXE>` prompt prints, but keystrokes never reach iPXE. An
# auto-chain script gets the install done without requiring keyboard
# at all; the shell fallback only matters when the chain fails, at
# which point you've got bigger problems to diagnose anyway.
#
# iPXE script syntax notes:
#   - `||` runs the next command on failure (single command — `;` is
#     a command separator, not a shell-style continuation).
#   - `shell` is interactive; control returns to the script when the
#     operator types `exit` (or Ctrl-D on some builds).
echo "[2/5] Rendering embedded script -> ${EMBED_FILE}"
cat > "${EMBED_FILE}" <<'EOF'
#!ipxe
echo
echo iPXE ${version} on ${net0/mac} (${manufacturer} ${product})
echo
dhcp || goto failed
echo Chaining http://bootserv01.lan/boot.ipxe ...
chain http://bootserv01.lan/boot.ipxe || goto failed
:failed
echo
echo Auto-boot failed. Manual retry:
echo   chain http://bootserv01.lan/boot.ipxe
:shell_loop
shell
goto shell_loop
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
