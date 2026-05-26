# Justfile for Ansible Playbooks
# Run 'just --list' to see all available commands

pwd := absolute_path(".")

# Default target
default:
    @just --list --unsorted

# Ping all servers
ping:
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
  ln -sf {{pwd}}/ansible/inventory.yaml "$HOME/.ansible/inventory/inventory.yaml"


# Run a playbook
run *options: check
    #!/usr/bin/env bash
    set -euo pipefail
    cd ansible
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

# Encrypt a variable with ansible-vault
secret-encrypt name:
    cd ansible && ansible-vault encrypt_string --vault-password-file ansible-pass --stdin-name {{name}}

# Decrypt & print a single value from group_vars/all/vault.yml.
# Pass a name (e.g. `just secret-decrypt vault_postgres_pass`), or
# omit it to fzf-pick from the vault's keys.
secret-decrypt name="":
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{name}}"
    cd ansible
    if [ -z "$name" ]; then
        name=$(grep -oE '^vault_[A-Za-z0-9_]+' group_vars/all/vault.yml | fzf)
    fi
    [ -n "$name" ] || { echo "No variable selected." >&2; exit 1; }
    ansible localhost -i inventory.yaml \
        -e @group_vars/all/vault.yml \
        --vault-password-file ansible-pass \
        -m debug -a "var=$name" 2>/dev/null

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


# READ-ONLY: inspect every physical host's disks (hypervisors + workers) and print a paste-ready `storage.disks` selector skeleton. Run after any disk add/swap
disk-plan:
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/17-host/15-storage-plan.yml


# READ-ONLY: refresh LVFS metadata on every baremetal and report available component firmware updates (NVMe SSDs, NICs, TPMs, etc.). Does NOT cover the HP MP9 G2 system BIOS — see runbooks/firmware-updates.md.
firmware-plan:
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/17-host/60-firmware-plan.yml


# DESTRUCTIVE: apply available firmware updates on ONE baremetal host. Some updates take effect only after reboot — drain the host first if it carries k3s workload (especially Longhorn replicas).
firmware-update host: check
    cd ansible && ansible-playbook --vault-password-file ansible-pass --limit {{host}} playbooks/poochella/infra/17-host/60-firmware-update.yml


# Run the full 17-host tier on every physical host (users, ssh-hardening, firewall, tailscale, node-exporter). Safe to re-run.
do-host-init: check
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/17-host/site.yml


# Build a per-host unattended Debian 13 install ISO (writes to img/debian/output/). Flash with img/burn-to-disc.sh.
baremetal-iso host: check
    {{pwd}}/img/debian/build.sh {{host}}


# Bring up (or reconcile) the foundation hypervisor (pve-home-01) + bootserv01 LXC + bootserv role. Run before any fresh-baremetal install — workers need bootserv01.lan to netboot.
do-foundation: check
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/16-foundation/site.yml


# Re-apply just the bootserv role on bootserv01 — fast iteration for iPXE/preseed template tweaks during the trial. Use after the LXC is up.
do-bootserv-config: check
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/16-foundation/90-bootserv.yml


# Push PXE-aware dnsmasq config + Mellanox static reservations to OPNsense. Re-run anytime debian_netboot.boot_macs or bootserv01 changes.
do-router-dhcp: check
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/10-router/20-dnsmasq.yml

