proxmox_endpoint = "https://pve-home-01.lan:8006"
proxmox_node     = "pve-home-01"

ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTl/C06oyAMQiGgvUyH4eT2C0sPsIEqnT2nDNHDQ5j9 ivanperdomo@Ivans-MacBook-Pro.local"

# Default VM template (debian-13). Per-VM `template_id` overrides this.
template_vm_id = 9001
template_ct_id = 9101

# All VM disks live on the `vms` Ceph RBD pool (cluster-shared), so any
# host can run any VM and live-migration works. The `node` field below
# only chooses *where the VM boots first* — it can be migrated later.

vms = {
  # ── Development ───────────────────────────────────────────────
  devbox01 = {
    hostname  = "devbox01"
    cores     = 4
    memory    = 8192
    disk_size = 100
    tags      = ["dev", "ivan"]
    # node      = "pve-home-01"
  }

  # ── Kubernetes control plane (1 per PVE host for HA) ──────────
  k8s-cp-01 = {
    hostname  = "kube-ctl-01"
    cores     = 2
    memory    = 4096
    disk_size = 30
    tags      = ["kube", "control-plane"]
    # node      = "pve-home-01"
  }
  k8s-cp-02 = {
    hostname  = "kube-ctl-02"
    cores     = 2
    memory    = 4096
    disk_size = 30
    tags      = ["kube", "control-plane"]
    # node      = "pve-home-02"
  }
  k8s-cp-03 = {
    hostname  = "kube-ctl-03"
    cores     = 2
    memory    = 4096
    disk_size = 30
    tags      = ["kube", "control-plane"]
    # node      = "pve-home-03"
  }

  # ── Kubernetes workers (1 per PVE host) ───────────────────────
  k8s-worker-01 = {
    hostname  = "kube-worker-01"
    cores     = 4
    memory    = 8192
    disk_size = 50
    tags      = ["kube", "worker"]
    # node      = "pve-home-01"
  }
  k8s-worker-02 = {
    hostname  = "kube-worker-02"
    cores     = 4
    memory    = 8192
    disk_size = 50
    tags      = ["kube", "worker"]
    # node      = "pve-home-02"
  }
  k8s-worker-03 = {
    hostname  = "kube-worker-03"
    cores     = 4
    memory    = 8192
    disk_size = 50
    tags      = ["kube", "worker"]
    # node      = "pve-home-03"
  }
}

containers = {
  # caddy01 = {
  #   hostname   = "caddy01"
  #   cores      = 1
  #   memory     = 512
  #   disk_size  = 4
  #   ip_address = "10.1.1.10/24"
  #   gateway    = "10.1.1.1"
  #   tags       = ["caddy", "webserver"]
  # }
  # nginx01 = {
  #   hostname  = "nginx01"
  #   cores     = 1
  #   memory    = 512
  #   disk_size = 8
  #   tags      = ["nginx", "webserver"]
  # }
}
