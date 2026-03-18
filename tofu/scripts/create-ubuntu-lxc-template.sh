# Download the Ubuntu 24.04 standard LXC template
pveam update
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst

# Create container (ID 9102)
pct create 9102 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname ubuntu-24-lxc-template \
  --memory 512 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,firewall=1 \
  --storage local-lvm \
  --unprivileged 1 \
  --features nesting=1

# Start, install packages, configure SSH
pct start 9102
pct exec 9102 -- apt-get update
pct exec 9102 -- apt-get install -y openssh-server curl wget sudo rsync htop

# Lock root password (no password login)
pct exec 9102 -- passwd -d root
pct exec 9102 -- passwd -l root

# Harden SSH: key-only auth, no password auth
pct exec 9102 -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
pct exec 9102 -- sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

pct stop 9102

# Convert to template
pct template 9102
