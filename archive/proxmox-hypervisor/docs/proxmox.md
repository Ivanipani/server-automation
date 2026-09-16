# Proxmox

Proxmox is the hypervisor of choice for the poochella project.

Hypervisors are primarily used in this project to slice up a baremetal into smaller, always-on infrastructure components.

Linux containers are preferred for simple, more focused workloads (boot/web server, single process).

Virtual machines are preferred for workloads requiring full system features, static DHCP reservation.

## Unattended OS installation

This project contains scripts and a Python TUI to flash a Proxmox ISO + preseed onto a USB for manual installation with automated steps.

In this manual process, each host's preseed, uniquely identifying the host's network + storage configuration is burned into the USB.
