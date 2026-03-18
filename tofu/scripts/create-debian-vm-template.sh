wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
sudo apt-get install libguestfs-tools
virt-customize -a debian-12-genericcloud-amd64.qcow2 --install qemu-guest-agent,curl,wget,sudo,rsync,htop
# virt-customize -a debian-12-genericcloud-amd64.qcow2 --run-command "sed -i 's|send host-name = gethostname();|send dhcp-client-identifier = hardware;|' /etc/dhcp/dhclient.conf"
# virt-customize -a debian-12-genericcloud-amd64.qcow2 --run-command "echo -n > /etc/machine-id"
  # Create a VM (ID 9001) with basic settings
sudo qm create 9001 --name debian-12-template \
--memory 2048 \
--cores 2 \
--cpu x86-64-v2-AES \
--net0 virtio,bridge=vmbr0,firewall=1 \
--scsihw virtio-scsi-single \
# --onboot 1 \
# --ostype l26

# Import the disk to local-lvm storage
sudo qm importdisk 9001 debian-12-genericcloud-amd64.qcow2 local-lvm

# Attach the imported disk (it shows as "unused0" after import)
sudo qm set 9001 --virtio0 local-lvm:vm-9001-disk-0,cache=writeback,iothread=1

# Set boot order to the disk
sudo qm set 9001 --boot order=virtio0

# Enable the QEMU guest agent
sudo qm set 9001 --agent enabled=1

# Convert to template
sudo qm template 9001

# Clean up downloaded images
mv debian-12-genericcloud-amd64.qcow2 /var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2.iso
# rm -f debian-12-genericcloud-amd64.qcow2
