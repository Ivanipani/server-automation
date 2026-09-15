pwd := absolute_path(".")

# All encryption key material lives in <repo-root>/secrets/ (git-ignored).
vault_pass := justfile_directory() / "secrets/ansible-pass"

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

# Check the control node has every CLI / python package / galaxy collection
# the components assume. Read-only; delegates to the control-node component's
# deps role (`components/control-node/roles/control-node-deps`).
check:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} \
        components/control-node/site.yml --tags deps

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
    selected=$(find playbooks components -name '*.yml' -type f \
        -not -path '*/roles/*' -not -path '*/vars/*' -not -path '*/tasks/*' \
        | sort | fzf)
    echo "Running $selected"
    ansible-playbook --vault-password-file {{vault_pass}} {{ options }} "$selected"

# Encrypt a variable with ansible-vault
secret-encrypt name:
    cd ansible && ansible-vault encrypt_string --vault-password-file {{vault_pass}} --stdin-name {{name}}

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
        --vault-password-file {{vault_pass}} \
        -m debug -a "var=$name" 2>/dev/null

# Layer-0 component: prepare THIS workstation to drive the fleet — vaulted
# `ansible` keypair at ~/.ssh/ansible{,.pub} so ansible.cfg's private_key_file
# resolves, ~/.ansible/inventory symlink so other projects can consume this
# inventory, and the dependency check. Run once on a fresh checkout; idempotent,
# re-run after rotating the keypair. Connection-local, so it needs no SSH key.
control-node *options:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} {{options}} \
        components/control-node/site.yml

# Assert-only smoke test for the control-node component. Mutates nothing.
control-node-verify:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} \
        components/control-node/tests/verify.yml

alias stage-ansible-key := control-node

# Layer-3 component: OPNsense DHCP/DNS/PXE + tailnet subnet router +
# node_exporter. Run via the poochella deployment wrapper, which builds
# the inventory-derived desired state (static leases, Unbound records)
# before applying components/router/site.yml. Must precede every other
# fleet component.
router *options:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} {{options}} \
        playbooks/poochella/infra/10-router.yml

# Assert-only smoke test for the router component. Mutates nothing.
router-verify:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} \
        components/router/tests/verify.yml

# Layer-3 component: Synology DSM (nas01) — file services + storage +
# ssh-access. Run via the poochella deployment wrapper, which builds
# the inventory-derived storage desired state (shares, NFS rules)
# before applying components/nas/site.yml.
nas *options:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} {{options}} \
        playbooks/poochella/infra/12-nas.yml

# Assert-only smoke test for the nas component. Mutates nothing.
nas-verify:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} \
        components/nas/tests/verify.yml

# Layer-1 component: users, ssh-hardening, firewall, MOTD, node-local
# disks, NFS mounts, NIC-offload workaround, firmware baseline,
# Tailscale, node_exporter — every baseline condition a baremetal Linux
# host needs. Run via the poochella deployment wrapper, which computes
# host_base_pve_host / host_disks_is_hypervisor / nfs_mounts_server
# from inventory before applying components/host-base/site.yml.
host-base *options:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} {{options}} \
        playbooks/poochella/infra/14-host-base.yml

# Assert-only smoke test for the host-base component. Mutates nothing.
host-base-verify:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} \
        components/host-base/tests/verify.yml

# READ-ONLY: report PRESENT/MISSING per declared partition on every physical host (host-disks role in info mode). Never halts. Safe anytime.
disk-plan:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} --tags storage -e host_disks_action=info playbooks/poochella/infra/14-host-base.yml

# READ-ONLY: refresh LVFS metadata on every baremetal and report available component firmware updates (NVMe SSDs, NICs, TPMs, etc.). Does NOT cover the HP MP9 G2 system BIOS — see runbooks/firmware-updates.md.
firmware-plan:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} playbooks/poochella/infra/firmware-plan.yml

sync-preseed-templates:
    cd ansible && ansible-playbook --vault-password-file {{vault_pass}} playbooks/poochella/infra/13-foundation/90-bootserv.yml --start-at-task "Copy iPXE chainload binaries into TFTP root"

