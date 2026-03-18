# Download the Debian 12 standard LXC template
pveam update
pveam download local debian-12-standard_12.7-1_amd64.tar.zst

# Create container (ID 9101)
pct create 9101 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname debian-12-lxc-template \
  --memory 512 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,firewall=1 \
  --storage local-lvm \
  --unprivileged 1 \
  --features nesting=1

# Start, install packages, configure SSH
pct start 9101
pct exec 9101 -- apt-get update
pct exec 9101 -- apt-get install -y openssh-server curl wget sudo rsync htop

# Lock root password (no password login)
pct exec 9101 -- passwd -d root
pct exec 9101 -- passwd -l root

# Harden SSH: key-only auth, no password auth
pct exec 9101 -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
pct exec 9101 -- sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

pct stop 9101

# Convert to template
pct template 9101
