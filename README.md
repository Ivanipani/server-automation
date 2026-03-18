# Poochella Server Automation

Declarative configuration for the poochella network and homelab cluster.

All configurations are managed using Ansible.

Contains declarative solutions for:

- DNS + DHCP config for LAN using pihole
- Development environment (programming tools, dotfiles)
- Network policies for VMs and containers
- Build + deploy static websites, webservers, reverse proxies

## Getting Started


```zsh
# check if all requirements are satisfied
just check

# install ansible (requires uv)
just install

# Run a playbook against the poochella cluster
just run
```

## Requirements

- Proxmox server, VMs, and LXCs are provisioned on LAN network
- SSH access to those hosts
- [uv](https://docs.astral.sh/uv/)

