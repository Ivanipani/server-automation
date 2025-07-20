#!/usr/bin/env bash
# setup_hypervisor.sh

HYPERVISOR_IP=${HYPERVISOR_IP:-192.168.0.213}
SSH_PUBLIC_KEY_PATH=${SSH_PUBLIC_KEY_PATH:-~/.ssh/ansible.pub}

# Local operations
if [ ! -f $SSH_PUBLIC_KEY_PATH ]; then
    echo "Creating SSH key pair..."
    ssh-keygen -t ed25519 -f ~/.ssh/ansible -N ""
fi

# Remote operations (executed as root on hypervisor)
ssh root@$HYPERVISOR_IP << 'EOF'
    # Create ansible user only if it doesn't exist
    if ! id "ansible" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo ansible
        echo "Created ansible user"
    else
        echo "ansible user already exists"
    fi
    
    # Create .ssh directory
    mkdir -p /home/ansible/.ssh
    chmod 700 /home/ansible/.ssh
    
    # Install sudo if not present
    if ! command -v sudo &> /dev/null; then
        apt update && apt install -y sudo
    fi
    
    # Add sudo access only if not already present
    if ! grep -q "ansible ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
        echo "ansible ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        echo "Added sudo access for ansible user"
    else
        echo "Sudo access already configured for ansible user"
    fi
    
    chmod 440 /etc/sudoers
EOF

ssh-copy-id -f -i $SSH_PUBLIC_KEY_PATH -t /home/ansible/.ssh/authorized_keys root@$HYPERVISOR_IP

# Copy SSH key to ansible user (only if not already present)
ssh root@$HYPERVISOR_IP << EOF
    chown -R ansible:ansible /home/ansible/
    chmod 600 /home/ansible/.ssh/authorized_keys
EOF


echo "Setup complete!"