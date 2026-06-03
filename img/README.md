# Overview

This directory contains scripts to manually flash removable media with images for various infrastructure components.

Supports booting/configuring:

- unattended proxmox 9.1 with preseed
- ipxe automated installer
- opnsense OS installation
- debian ISO with bundled preseed file
- debian 13 live image (rescue/debug tool)

## Note on PXE booting

ISOs for Debian 13, proxmox 9.1 are created and distributed via HTTP in the bootserv.yml playbook,
which creates an LXC with nginx+dnsmasq to serve per-host preseed/boot files generated from the ansible inventory.yml
