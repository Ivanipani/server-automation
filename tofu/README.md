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
        ├── variables.tf  # var.proxmox_api_token (string)
        ├── outputs.tf
        ├── versions.tf
        └── terraform.tfstate  # created on first apply
```

## Adding a new hypervisor

1. Add the host to `ansible/inventory.yaml` (host entry +
   `all.vars.proxmox_endpoints` + `all.vars.template_vm_ids` +
   `all.vars.template_ct_ids`) and to `proxmox_api_tokens` in
   `ansible/group_vars/all/vars.yml`.
2. `cp -r tofu/per-node/pve-home-01 tofu/per-node/<new-host>`.
3. Edit `local.hypervisor_name` in the new directory's `main.tf` to the
   new host's inventory key. Nothing else changes — endpoint comes from
   inventory, token comes from Ansible at apply time.

## Driving Tofu

Apply is driven from Ansible:

- `playbooks/poochella/infra/13-foundation/80-tofu-infra-lxcs.yml` —
  loops over the `foundation` group, runs a targeted apply
  (`-target=module.hypervisor.module.infra_lxcs`) per foundation host
  to bring up only the infra LXCs (bootserv01 today).
- `playbooks/poochella/infra/30-guests/10-opentofu.yml` — loops over
  every hypervisor, runs the full per-node apply.

Both pass each iteration's token via `TF_VAR_proxmox_api_token`, sourced
per-iteration from the `proxmox_api_tokens` map in
`group_vars/all/vars.yml`.

## Manual invocation (rare)

```sh
cd tofu/per-node/<host>
TF_VAR_proxmox_api_token="<the_token>" tofu init
TF_VAR_proxmox_api_token="<the_token>" tofu plan
TF_VAR_proxmox_api_token="<the_token>" tofu apply
```
