# Justfile for Ansible Playbooks
# Run 'just --list' to see all available commands

pwd := absolute_path(".")

# Default target
default:
    @just --list --unsorted

# Ping all servers
ping:
    #!/usr/bin/env bash
    ansible all -m ping


# Check requirements are installed on control node
check:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0

    echo "Checking control node dependencies..."

    # Check required CLI tools
    for cmd in ansible ansible-playbook ansible-vault ssh fzf helm; do
        if which "$cmd" > /dev/null 2>&1; then
            echo "  ✓ $cmd"
        else
            echo "  ✗ $cmd is missing"
            errors=$((errors + 1))
        fi
    done

    # Check required Python packages in the ansible-core environment
    ansible_python=$(ansible --version 2>/dev/null | grep 'python version' | sed 's/.*(\(.*\))/\1/' | awk '{print $1}')
    if [ -z "$ansible_python" ]; then
        echo "  ✗ Could not determine ansible's Python interpreter"
        errors=$((errors + 1))
    else
        for pkg in passlib ; do
            if "$ansible_python" -c "import $pkg" 2>/dev/null; then
                echo "  ✓ Python package: $pkg"
            else
                echo "  ✗ Python package: $pkg is missing (install with: uv tool install ansible-core --with $pkg --force)"
                errors=$((errors + 1))
            fi
        done
    fi

    # Check required Ansible collections
    for collection in community.general community.postgresql ansible.posix oxlorg.opnsense; do
        if ansible-galaxy collection list "$collection" 2>/dev/null | grep -q "$collection"; then
            echo "  ✓ Ansible collection: $collection"
        else
            echo "  ✗ Ansible collection: $collection is missing (install with: ansible-galaxy collection install $collection)"
            errors=$((errors + 1))
        fi
    done

    if [ "$errors" -gt 0 ]; then
        echo ""
        echo "$errors dependency issue(s) found."
        exit 1
    else
        echo ""
        echo "All dependencies satisfied."
    fi


# Install all dependencies needed for this project
install:
    echo "Installing ansible..."
    uv tool install ansible-core --with passlib --with httpx --force
    echo "Installing required ansible collections..."
    ansible-galaxy install -r requirements.yml


# symlink inventory.yaml into $HOME. Allows other projects to use this inventory as the source of truth
symlink-inventory:
  mkdir -p "$HOME/.ansible/inventory"
  ln -sf {{pwd}}/inventory.yaml "$HOME/.ansible/inventory/inventory.yaml"


# Run a playbook
run *options: check
    #!/usr/bin/env bash
    set -euo pipefail
    selected=$(find playbooks -name '*.yml' -type f | sort | fzf)
    echo "Running $selected"
    ansible-playbook --vault-password-file ansible-pass {{ options }} "$selected"

# Run the test playbook
test: check
    #!/usr/bin/env bash
    set -euo pipefail
    tags=$(grep 'tags:' test/test.yml | awk '{gsub(/[\[\]]/, "", $NF); print $NF}' | fzf --multi | paste -sd, -)
    if [ -z "$tags" ]; then
        echo "No tags selected."
        exit 0
    fi
    ansible-playbook -i inventory.yaml test/test.yml --tags "$tags"

tofu-validate:
    cd tofu && tofu validate

# Initialize OpenTofu providers
tofu-init: tofu-validate
    cd tofu && tofu init

# Preview infrastructure changes
tofu-plan: tofu-validate
    cd tofu && tofu plan

# Apply infrastructure changes
tofu-apply: tofu-validate
    cd tofu && tofu apply

# Encrypt a variable with ansible-vault
secret-encrypt name:
    ansible-vault encrypt_string --vault-password-file ansible-pass --stdin-name {{name}}

# Clear and re-seed SSH host keys for every host in the inventory
ssh-refresh:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(ansible-inventory --list 2>/dev/null | python3 -c "
    import json, sys
    data = json.load(sys.stdin)
    meta = data.get('_meta', {}).get('hostvars', {})
    out = set()
    for host, vars in meta.items():
        out.add(host)
        if 'ansible_host' in vars:
            out.add(vars['ansible_host'])
    print('\n'.join(sorted(out)))
    ")
    for t in $targets; do
        echo "Refreshing $t..."
        ssh-keygen -R "$t" 2>/dev/null || true
        ip=$(dig +short "$t" 2>/dev/null | head -n1 || true)
        if [ -n "$ip" ]; then
            ssh-keygen -R "$ip" 2>/dev/null || true
        fi
        ssh-keyscan "$t" 2>/dev/null >> "$HOME/.ssh/known_hosts" || true
    done
    echo "Done."

# Init hypervisor for development
do-hypervisor-init:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/02-bootstrap-hypervisor.yml
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/trunk/07-sessions-and-shell.yml
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/trunk/07-users.yml
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/trunk/08-dev-tools.yml

# Form corosync clusters PER GROUP (run after do-hypervisor-init).
# Scoped to hosts under `pve_cluster` child groups; a NO-OP when every
# node is standalone (poochella's current state). Stays in the bootstrap
# so adding a cluster group is the only change required.
do-cluster-init:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/02b-cluster-hypervisor.yml

# Carve the boot-disk tail into `vm-storage` (~45%) + `longhorn` (rest)
# GPT partitions. DESTRUCTIVE on first run — requires
# `confirm_carve_data_disk: true` in group_vars/baremetal.yml AND PVE
# installed with `lvm.hdsize = 100`.
do-partition-disks:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/03-partition-disks.yml

# Build node-local LVM-thin pools on the carved partitions and register
# them as PVE storage (`vms`, `longhorn-data`). Requires
# `do-partition-disks` to have been run first.
do-provision-storage:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/03b-provision-storage.yml

# Format + mount the k3s workers' second disk at /var/lib/longhorn
# (ground-prep for a future Longhorn install). Requires worker VMs
# provisioned with a `vm.data_disk_size` declared in inventory.yaml.
do-longhorn-storage:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/09b-longhorn-storage.yml

# Configure OPNsense dnsmasq static leases for baremetal
do-router-dhcp:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/01b-router-dnsmasq.yml

# Configure OPNsense Unbound host overrides (wildcard DNS for k8s ingress)
do-router-dns:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/01c-router-unbound.yml

# Install Prometheus node_exporter on Proxmox baremetal hosts
do-node-exporter:
    ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/11-node-exporter.yml
