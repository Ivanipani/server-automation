# Typed variable declarations for the VM golden-image Packer project.
# Static defaults live in variables.auto.pkrvars.hcl (auto-loaded);
# host-specific values (mount path, SSH key contents) are passed by
# 20-hypervisor/40-bake-images.yml via `-var k=v` at `packer build` time.

variable "image_family" {
  type        = string
  description = "Image family identifier, used as the filename prefix on the NAS (e.g. debian-13)."
}

variable "debian_image_url" {
  type        = string
  description = "Pinned upstream Debian generic-cloud qcow2 URL. Bump with debian_image_checksum_url together to refresh."
}

variable "debian_image_checksum_url" {
  type        = string
  description = "URL of the upstream SHA512SUMS file matching debian_image_url."
}

variable "ansible_pubkey" {
  type        = string
  description = "Contents (not path) of the SSH public key authorised on the baked image's `ansible` user. Injected by 40-bake-images.yml."
}

variable "output_dir" {
  type        = string
  description = "Working directory under which Packer writes per-build subdirectories on the build host."
  default     = "/var/tmp/packer-images"
}

variable "nas_images_local_dir" {
  type        = string
  description = <<-EOT
    Local path on the build host where the post-processor writes the
    dated qcow2 + sha256 + the *-latest.qcow2 symlinks. Has to be the
    PVE `iso` content subpath inside the NFS-mounted `proxmox` share,
    i.e. /mnt/nas/proxmox/template/iso — PVE's dir storage convention
    looks here for ISO content. Injected by 40-bake-images.yml.
  EOT
}
