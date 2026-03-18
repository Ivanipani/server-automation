wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sudo apt-get install libguestfs-tools
virt-customize -a noble-server-cloudimg-amd64.img --install qemu-guest-agent,curl,wget,sudo,rsync,htop
  # Create a VM (ID 9002) with basic settings
sudo qm create 9002 --name ubuntu-24-template \
--memory 2048 \
--cores 2 \
--cpu x86-64-v2-AES \
--net0 virtio,bridge=vmbr0,firewall=1 \
--scsihw virtio-scsi-single \
# --onboot 1 \
# --ostype l26

# Import the disk to local-lvm storage
sudo qm importdisk 9002 noble-server-cloudimg-amd64.img local-lvm

# Attach the imported disk (it shows as "unused0" after import)
sudo qm set 9002 --virtio0 local-lvm:vm-9002-disk-0,cache=writeback,iothread=1

# Set boot order to the disk
sudo qm set 9002 --boot order=virtio0

# Enable the QEMU guest agent
sudo qm set 9002 --agent enabled=1

# Convert to template
sudo qm template 9002

# Clean up downloaded images
mv noble-server-cloudimg-amd64.img /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img.iso
