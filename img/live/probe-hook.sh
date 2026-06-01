#!/bin/sh
# live-config medium hook — baked onto the probe ISO at /live/config-hooks/.
#
# Enabled by the boot parameter `live-config.hooks=medium`, which tells
# live-config to run every hook found in /live/config-hooks/ on the boot medium
# (see live-config(7)). It runs once at boot, as root, in the writable live
# overlay — so /etc, /root and /usr/local are writable here.
#
# It does only lightweight wiring: install the probe, enable root autologin on
# tty1, and arrange the probe + a tiny HTTP server to run from that login shell.
# The probe itself runs from the login shell (not here) so that DHCP is already
# up and the served URL shows a real IP.

set -eu

# locate the boot medium (live-config mounts it at one of these)
medium=""
for m in /run/live/medium /lib/live/mount/medium; do
    [ -f "$m/poochella/probe.sh" ] && { medium="$m"; break; }
done

# 1. install the probe
if [ -n "$medium" ]; then
    install -D -m 0755 "$medium/poochella/probe.sh" /usr/local/sbin/poochella-probe
fi

# 2. root autologin on tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

# 3. run the probe + serve it, once, from the autologin login shell
cat > /root/.bash_profile <<'EOF'
# poochella probe autostart (idempotent within a boot)
if [ -z "${POOCHELLA_PROBE_DONE:-}" ] && command -v poochella-probe >/dev/null 2>&1; then
    export POOCHELLA_PROBE_DONE=1
    mkdir -p /run/poochella
    poochella-probe | tee /run/poochella/inventory-fragment.yaml
    ( cd /run/poochella && python3 -m http.server 8000 >/run/poochella/http.log 2>&1 & )
    echo
    echo "=================================================================="
    echo " poochella hardware probe complete."
    echo " Fragment saved to /run/poochella/inventory-fragment.yaml"
    echo " Pull it from your laptop with one of:"
    ip -4 -o addr show scope global 2>/dev/null \
      | awk -F'[ /]+' '{print "   curl http://"$4":8000/inventory-fragment.yaml"}'
    echo
    echo " (re-run any time with: poochella-probe)"
    echo "=================================================================="
fi
EOF
