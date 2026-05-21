# Debian 13 (Trixie) golden VM image. Boots the upstream generic-cloud
# qcow2 under qemu (KVM accelerator on the build host), seeds NoCloud
# over Packer's HTTP server via the SMBIOS `ds=nocloud-net;s=` trick,
# lets cloud-init create a transient `packer` user, then runs the
# repo's `golden-image-bake` Ansible role to install the `ansible`
# user/key + sysprep. The resulting qcow2 is shasummed and written
# directly to the NAS via the NFS mount the build host has at
# /mnt/nas/proxmox (set up by 20-hypervisor/35-nfs-mounts.yml).
# The `*-latest.qcow2` symlink is atomically repointed at the new
# dated artifact so concurrent readers (PVE nodes referencing
# `nas-images:iso/<family>-latest.qcow2`) see only the old OR the
# new target, never a half-updated symlink.

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.0.10"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.1"
    }
  }
}

locals {
  # Computed once at HCL parse time so every reference (output dir, file
  # name, post-processor) sees the SAME value. UTC, minute resolution.
  build_timestamp = formatdate("YYYYMMDDhhmm", timestamp())
  output_name     = "${var.image_family}-${local.build_timestamp}.qcow2"
}

source "qemu" "debian-13" {
  # Use the upstream cloud qcow2 as the boot disk (no installer phase).
  iso_url          = var.debian_image_url
  iso_checksum     = "file:${var.debian_image_checksum_url}"
  disk_image       = true
  use_backing_file = false
  format           = "qcow2"

  # NoCloud-net seed: cloud-init reads SMBIOS serial for the `ds=` URL,
  # then GETs user-data + meta-data from Packer's HTTP server. Avoids
  # building a cidata ISO on the fly.
  #
  # CRITICAL: must be `http_content` (not `http_directory`). Both serve
  # the files, but only `http_content` runs values through Packer's
  # template engine — needed so `{{ .SSHPublicKey }}` in user-data
  # gets substituted with the temp RSA key Packer generates for SSH.
  # With `http_directory` the file is served byte-for-byte, cloud-init
  # ingests the literal `{{ .SSHPublicKey }}` string as the "key", and
  # Packer's SSH login attempt fails ("unable to authenticate").
  # `file()` reads the file at HCL parse time; the string then enters
  # http_content where Packer's serve-time interpolation happens.
  http_content = {
    "/meta-data" = file("${path.root}/http/meta-data")
    "/user-data" = file("${path.root}/http/user-data")
  }
  qemuargs = [
    ["-smbios", "type=1,serial=ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/"],
  ]

  cpus              = 2
  memory            = 2048
  disk_size         = "8G"
  accelerator       = "kvm"
  headless          = true
  net_device        = "virtio-net"
  disk_interface    = "virtio"
  # Pin VNC port so the SSH tunnel target is deterministic across runs.
  # Connect via `ssh -L 5901:127.0.0.1:5901 ansible@<build-host>` then
  # point any VNC viewer at localhost:5901. Only bound on 127.0.0.1
  # of the build host, so the SSH tunnel is the only way to reach it.
  vnc_port_min      = 5901
  vnc_port_max      = 5901
  vnc_bind_address  = "127.0.0.1"
  # NB: `format = "qcow2"` is set above in the iso_url group; redeclaring
  # it here triggers Packer's "attribute redefined" error. One declaration
  # suffices for both source-disk parsing and output format.
  vm_name           = local.output_name
  output_directory  = "${var.output_dir}/${var.image_family}-${local.build_timestamp}"

  # SSH bootstrap: NoCloud creates the `packer` user with this auto-
  # generated public key in authorized_keys; packer connects in once
  # cloud-init applies the config.
  ssh_username     = "packer"
  ssh_timeout      = "15m"

  shutdown_command = "sudo -S shutdown -P now"
}

build {
  name    = "debian-13"
  sources = ["source.qemu.debian-13"]

  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/bake.yml"
    user          = "packer"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_pubkey=${var.ansible_pubkey}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      # The bake role lives at the repo root, but 40-bake-images.yml
      # rsyncs both that role AND its `apt-no-auto-upgrades` dependency
      # into /opt/packer-roles/ on the build host so we don't carry the
      # whole repo. Override that path here for hand-runs.
      "--roles-path", "/opt/packer-roles",
    ]
  }

  # sha256 + write-to-NFS + atomic latest-symlink flip. Runs on the
  # build host (the `shell-local` post-processor inherits the packer
  # process's env and CWD). Everything is a LOCAL filesystem operation
  # because the destination is NFS-mounted on this host — no SSH, no
  # rsync, no remote command shell.
  post-processor "shell-local" {
    inline_shebang = "/bin/bash -eu"
    inline = [
      "cd '${var.output_dir}/${var.image_family}-${local.build_timestamp}'",
      # 1. Checksum the produced qcow2.
      "sha256sum '${local.output_name}' > '${local.output_name}.sha256'",
      # 2. Copy artifact + sha256 to the NFS-mounted target. `install`
      #    with -m 0644 fixes mode to a predictable value regardless
      #    of the build host's umask (qcow2s must be world-readable so
      #    DSM's web server can also serve them under the HTTPS URL).
      "install -m 0644 '${local.output_name}'        '${var.nas_images_local_dir}/${local.output_name}'",
      "install -m 0644 '${local.output_name}.sha256' '${var.nas_images_local_dir}/${local.output_name}.sha256'",
      # 3. Atomic alias update — `mv -Tf` is rename(2)-atomic on a
      #    single filesystem (NFSv4 honors this for renames within
      #    the same export), so HTTPS / NFS readers always see the
      #    old OR the new symlink target, never a half-updated one.
      "ln -sf '${local.output_name}'        '${var.nas_images_local_dir}/${var.image_family}-latest.qcow2.new'",
      "ln -sf '${local.output_name}.sha256' '${var.nas_images_local_dir}/${var.image_family}-latest.qcow2.sha256.new'",
      "mv -Tf '${var.nas_images_local_dir}/${var.image_family}-latest.qcow2.new'        '${var.nas_images_local_dir}/${var.image_family}-latest.qcow2'",
      "mv -Tf '${var.nas_images_local_dir}/${var.image_family}-latest.qcow2.sha256.new' '${var.nas_images_local_dir}/${var.image_family}-latest.qcow2.sha256'",
    ]
  }
}
