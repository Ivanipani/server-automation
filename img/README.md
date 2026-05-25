# Overview

This directory contains scripts to flash removable media with images for various infrastructure components.

Supports booting/configuring:

- unattended proxmox 9.1 with preseed
- ipxe automated installer + rescue
- opnsense OS installation
- debian ISO with bundled preseed file

## Note on PXE booting

It's handled by the bootserv.yml playbook, which creates an LXC with nginx+dnsmasq to serve per-host preseed/boot
files generated from the ansible inventory.yml
