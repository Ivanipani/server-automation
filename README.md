# Poochella Server Automation

Declarative configuration for the poochella network and homelab cluster.

All configurations are managed using Ansible.

Contains declarative solutions for:

- Configure DNS + DHCP config for LAN using pihole
- Development environment (programming tools, dotfiles)
- Network policies for VMs and containers
- Build + deploy static websites, webservers, reverse proxies

## Getting Started


```zsh
# check if all requirements are satisfied
just check

# configure poochella cluster
just setup

# Run a single playbook
just run-single

# install servers.yml into $HOME
just symlink-servers
```
