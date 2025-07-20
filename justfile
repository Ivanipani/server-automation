# Justfile for Ansible Playbooks
# Run 'just --list' to see all available commands

# Default target
default:
    @just --list

# Ping all servers
ping: check-ansible
    #!/usr/bin/env bash
    ansible all -m ping -K

# Run all playbooks
run-all : check-ansible
    #!/usr/bin/env bash
    ansible-playbook playbooks/*.yml -K

# Run a single playbook
run-single: check-ansible
  #!/usr/bin/env nu
  let selected_playbook = ls playbooks | each {|playbook| $playbook.name | path basename} | input list
  print $"Running ($selected_playbook)"
  ansible-playbook $"playbooks/($selected_playbook)" -K

# Check if ansible is installed
check-ansible:
    #!/usr/bin/env bash
    which ansible > /dev/null && echo "Ansible is installed" || (echo "Error: ansible is required but not installed. Install with: uv tool install ansible" && exit 1)
    which ansible-playbook > /dev/null && echo "Ansible-playbook is installed" || (echo "Error: ansible-playbook is required but not installed. Install with: uv tool install ansible" && exit 1)

