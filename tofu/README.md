# tofu/

State-per-hypervisor OpenTofu layout. Every Proxmox hypervisor in the
fleet is a fully standalone PVE host (no clustering — see
`ansible/playbooks/poochella/infra/20-hypervisor/20-cluster.yml`'s
assertion), so each gets its own Tofu workspace with its own state.

```
tofu/
├── modules/
│   ├── hypervisor/  # inventory walk + vm + lxc instantiation for one host
│   ├── vm/          # one resource: proxmox_virtual_environment_vm
│   └── lxc/         # one resource: proxmox_virtual_environment_container
└── per-node/
    └── pve-home-01/ # per-hypervisor workspace + state
        ├── main.tf       # local.hypervisor_name = "pve-home-01" + module.hypervisor
        ├── provider.tf   # single proxmox provider (no aliases)
        ├── variables.tf  # var.proxmox_username (default advanceteam@pve) + var.proxmox_password
        ├── outputs.tf
        ├── versions.tf
        └── terraform.tfstate  # created on first apply
```

## Adding a new hypervisor

1. Add the host to `ansible/inventory.yaml` (host entry +
   `all.vars.proxmox_endpoints` + `all.vars.template_vm_ids` +
   `all.vars.template_ct_ids`). No per-node secret to add — Tofu
   authenticates to every node as the shared `advanceteam@pve` account
   (one well-known password), created by
   `20-hypervisor/15-tofu-service-account.yml`.
2. `cp -r tofu/per-node/pve-home-01 tofu/per-node/<new-host>`.
3. Edit `local.hypervisor_name` in the new directory's `main.tf` to the
   new host's inventory key. Nothing else changes — endpoint comes from
   inventory, password comes from Ansible at apply time.

## Driving Tofu

Apply is driven from Ansible:

- `playbooks/poochella/infra/13-foundation/80-tofu-infra-lxcs.yml` —
  loops over the `foundation` group, runs a targeted apply
  (`-target=module.hypervisor.module.infra_lxcs`) per foundation host
  to bring up only the infra LXCs (bootserv01 today).
- `playbooks/poochella/infra/30-guests/10-opentofu.yml` — loops over
  every hypervisor, runs the full per-node apply.

Both authenticate as the shared `advanceteam@pve` service account,
passing the one well-known password via `TF_VAR_proxmox_password`
(sourced from `advanceteam_user_pass` in `group_vars/all/vars.yml`). The
username comes from the `proxmox_username` Tofu variable (default
`advanceteam@pve`), so only the password is supplied at apply time.

## Manual invocation (rare)

```sh
cd tofu/per-node/<host>
export TF_VAR_proxmox_password="<advanceteam@pve password>"
tofu init
tofu plan
tofu apply
# Override the user if needed: TF_VAR_proxmox_username="other@pve"
```
