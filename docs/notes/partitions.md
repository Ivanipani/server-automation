# Disk Partition management

There are many utilities to manage disk partitions. Lots have overlap.

This document captures commands to manually administer partitions on Linux.

## Recipes

List partitions: `lsblk`

> `gdisk` is an interactive utility to do partition management. Use this to explore and develop automated workflows

Delete a partition:

1. If it's mounted, first unmount it with `umount`
2. `sudo sgdisk -d /dev/path-to-partition`
3. Tell the kernel we have made a change to the partitions: `partprobe`
4.
