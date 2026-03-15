# Justfile for Ansible Playbooks
# Run 'just --list' to see all available commands

pwd := absolute_path(".")

# Default target
default:
    @just --list

# symlink servers.yml into $HOME
symlink-servers:
  mkdir -p "$HOME/.ansible/inventory"
  ln -sf {{pwd}}/servers.yml "$HOME/.ansible/inventory/servers.yml"


# Ping all servers
ping: check-ansible
    #!/usr/bin/env bash
    ansible all -m ping

# Run the full poochella cluster setup in correct dependency order
setup: check
    #!/usr/bin/env bash
    ansible-playbook playbooks/site.yml

# Run all playbooks
run-all : check-ansible
    #!/usr/bin/env bash
    ansible-playbook playbooks/*.yml

# Run a single playbook
run-single: check-ansible
    #!/usr/bin/env bash
    set -euo pipefail
    selected=$(ls playbooks/*.yml | xargs -n1 basename | fzf)
    echo "Running $selected"
    ansible-playbook "playbooks/$selected"

# Check if ansible is installed
check-ansible:
    #!/usr/bin/env bash
    which ansible > /dev/null && echo "Ansible is installed" || (echo "Error: ansible is required but not installed. Install with: uv tool install ansible" && exit 1)
    which ansible-playbook > /dev/null && echo "Ansible-playbook is installed" || (echo "Error: ansible-playbook is required but not installed. Install with: uv tool install ansible" && exit 1)

# Validate all required software and Python dependencies on the control node
check: check-ansible
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0

    echo "Checking control node dependencies..."

    # Check required CLI tools
    for cmd in ansible ansible-playbook ansible-vault ssh fzf; do
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
        for pkg in passlib; do
            if "$ansible_python" -c "import $pkg" 2>/dev/null; then
                echo "  ✓ Python package: $pkg"
            else
                echo "  ✗ Python package: $pkg is missing (install with: uv tool install ansible-core --with $pkg --force)"
                errors=$((errors + 1))
            fi
        done
    fi

    # Check required Ansible collections
    for collection in community.general community.postgresql ansible.posix; do
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


# Set up macOS development environment
mac: check-ansible
    #!/usr/bin/env bash
    ansible-playbook playbooks/local-mac.yml

# Run the test playbook with interactive tag selection via fzf
test-run:
    #!/usr/bin/env bash
    set -euo pipefail
    tags=$(grep 'tags:' test/test.yml | awk '{gsub(/[\[\]]/, "", $NF); print $NF}' | fzf --multi | paste -sd, -)
    if [ -z "$tags" ]; then
        echo "No tags selected."
        exit 0
    fi
    ansible-playbook -i servers.yml test/test.yml --tags "$tags"
