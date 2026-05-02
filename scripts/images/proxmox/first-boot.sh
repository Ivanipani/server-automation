#!/bin/sh
# Proxmox auto-install first-boot hook (ordering = before-network).
#
# The Proxmox installer always writes a static /etc/network/interfaces, even
# with `[network] source = "from-dhcp"` (it captures the install-time DHCP
# lease and freezes it as static). This hook flips vmbr0 to runtime DHCP and
# installs a oneshot that resyncs /etc/hosts with the actual leased IP, since
# pve-cluster / pveproxy identity depend on /etc/hosts matching the live IP.

set -eu

ifaces=/etc/network/interfaces
tmp=$(mktemp)

awk '
  /^iface vmbr0 inet / {
    sub(/inet [a-z]+/, "inet dhcp")
    in_vmbr0 = 1
    print
    next
  }
  /^(auto |iface |allow-)/ {
    in_vmbr0 = 0
    print
    next
  }
  in_vmbr0 && /^[[:space:]]*(address|gateway|netmask)([[:space:]]|$)/ {
    next
  }
  { print }
' "$ifaces" > "$tmp"
mv "$tmp" "$ifaces"
chmod 0644 "$ifaces"

cat >/usr/local/sbin/pve-host-fixup.sh <<'INNER'
#!/bin/sh
set -eu
fqdn=$(hostname -f 2>/dev/null || hostname)
short=$(hostname -s 2>/dev/null || hostname)
ip=$(ip -4 -o addr show dev vmbr0 scope global 2>/dev/null \
     | awk '{print $4}' | cut -d/ -f1 | head -n1)
[ -n "$ip" ] || exit 0
current=$(awk -v f="$fqdn" '$2==f || $3==f {print $1; exit}' /etc/hosts)
[ "$current" = "$ip" ] && exit 0
sed -i -E "/[[:space:]]${fqdn}([[:space:]]|\$)/d" /etc/hosts
printf '%s %s %s\n' "$ip" "$fqdn" "$short" >> /etc/hosts
INNER
chmod 0755 /usr/local/sbin/pve-host-fixup.sh

cat >/etc/systemd/system/pve-host-fixup.service <<'UNIT'
[Unit]
Description=Sync /etc/hosts with the DHCP-assigned vmbr0 address
After=network-online.target
Wants=network-online.target
Before=pve-cluster.service pveproxy.service pvedaemon.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-host-fixup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable pve-host-fixup.service
