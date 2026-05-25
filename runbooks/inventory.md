# Poochella Inventory

All automations in this project depend on and reference the declarative cluster inventory defined in [inventory.yml](/ansible/inventory.yaml)

This project aims to be a closed-loop system with declarative, hyperconverged inventory management.

If the component is not listed in the inventory, it will most likely not exist on the network.

Infrastructure playbooks in [site.yml](/ansible/playbooks/poochella/site.yml) are arranged in dependency order.
All playbooks aim to be idempotent and safe to rerun.

The general bootstrap order to create the cluster from scratch:

1. Router (DNS, DHCP, unit configuration)
2. NAS
3. pve-home-01 (first hypervisor, pxe boot host)
4. all other servers

## DHCP / DNS guarantees

Any device that wants to receive a known address via static reservation in OPNSense can do so by declaring its IPv4 network address + MAC.

It is the cluster owner's responsibility to ensure accurate MAC information in the inventory file.
Incorrect or missing information here can cause DNS to break, automated builds to fail, etc.

