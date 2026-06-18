pwd := absolute_path(".")

# Default target
default:
    @just --list --unsorted

# Needs docker buildx + a GAR login (`gcloud auth configure-docker us-east4-docker.pkg.dev`).
# Defaults to amd64 (the k3s cluster nodes' arch); override e.g. `just ci-builder arm64`.
# Build & push the Tekton CI builder image to GAR via Pants (buildx --platform).
ci-builder arch="amd64" tag="latest":
    CI_BUILDER_PLATFORM=linux/{{arch}} CI_BUILDER_TAG={{tag}} \
        pants publish k8s/infra/cicd/images/ci-builder:ci-builder

# Ping all servers
ping:
    cd ansible && ansible all -m ping

# Check requirements are installed on control node
check:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0

    echo "Checking control node dependencies..."

    # Check required CLI tools
    for cmd in ansible ansible-playbook ansible-vault ssh fzf helm kubectl flux; do
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


# Run a playbook
run *options: check
    #!/usr/bin/env bash
    set -euo pipefail
    cd ansible
    selected=$(find playbooks -name '*.yml' -type f | sort | fzf)
    echo "Running $selected"
    ansible-playbook --vault-password-file ansible-pass {{ options }} "$selected"
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

# Materialize the fleet-wide `ansible` SSH keypair onto this control node
# from the vault (~/.ssh/ansible 0600 + ~/.ssh/ansible.pub 0644). Run once
# on a fresh checkout so ansible.cfg's private_key_file resolves. Idempotent;
# re-run after rotating the keypair. Connection-local, so it needs no SSH key.
# symlink inventory.yaml into $HOME. Allows other projects to use this inventory as the source of truth
stage-ansible-key:
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/00-control-node/10-stage-ansible-key.yml
    mkdir -p "$HOME/.ansible/inventory"
    ln -sf {{pwd}}/ansible/inventory.yaml "$HOME/.ansible/inventory/inventory.yaml"


# READ-ONLY: report PRESENT/MISSING per declared partition on every physical host (host-disks role in info mode). Never halts. Safe anytime.
disk-plan:
    cd ansible && ansible-playbook --vault-password-file ansible-pass -e host_disks_action=info playbooks/poochella/infra/17-host/15-storage.yml

# READ-ONLY: refresh LVFS metadata on every baremetal and report available component firmware updates (NVMe SSDs, NICs, TPMs, etc.). Does NOT cover the HP MP9 G2 system BIOS — see runbooks/firmware-updates.md.
firmware-plan:
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/17-host/60-firmware-plan.yml

sync-preseed-templates:
    cd ansible && ansible-playbook --vault-password-file ansible-pass playbooks/poochella/infra/13-foundation/90-bootserv.yml --start-at-task "Copy iPXE chainload binaries into TFTP root"

