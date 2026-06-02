# tofu/

Flat, single-root OpenTofu layout. Every Proxmox hypervisor in the fleet
is a fully standalone PVE host (no clustering — see
`ansible/playbooks/poochella/infra/20-hypervisor/20-cluster.yml`'s
assertion), so each needs its own state — but **not** its own directory.
One config (`tofu/node/`) serves every node; state is isolated by a named
**tofu workspace** per host. To talk to a different hypervisor you point
`var.proxmox_endpoint` at a different URL and select that node's
workspace — you never copy a folder.

```
tofu/
├── modules/
│   ├── hypervisor/  # inventory walk + vm + lxc instantiation for one host
│   ├── vm/          # one resource: proxmox_virtual_environment_vm
│   └── lxc/         # one resource: proxmox_virtual_environment_container
└── node/            # THE flat root — one workspace per hypervisor
    ├── main.tf       # endpoint + hypervisor_name (defaults to workspace)
    ├── provider.tf   # single proxmox provider (no aliases)
    ├── variables.tf  # proxmox_endpoint (URL) + hypervisor_name + username/password
    ├── outputs.tf
    ├── versions.tf
    └── terraform.tfstate.d/<host>/terraform.tfstate  # per-workspace state
```

## Adding a new hypervisor

1. Add the host to `ansible/inventory.yaml` (host entry +
   `all.vars.proxmox_endpoints` + `all.vars.template_vm_ids` +
   `all.vars.template_ct_ids`). No per-node secret — Tofu authenticates
   to every node as the shared `advanceteam@pve` account (one well-known
   password), created by `20-hypervisor/15-tofu-service-account.yml`.
2. **That's it.** No directory to copy. The Ansible drivers loop the
   `hypervisors` group and create a fresh `tofu workspace` for the new
   node on first apply; its endpoint comes from `proxmox_endpoints` and
   its password from Ansible at apply time.

## Driving Tofu

Apply is driven from Ansible against the one `tofu/node/` root, selecting
the target node with the `workspace` parameter + the `proxmox_endpoint`
/ `hypervisor_name` variables:

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
cd tofu/node
tofu workspace select pve-home-01        # or `tofu workspace new pve-home-01`
export TF_VAR_proxmox_password="<advanceteam@pve password>"
tofu init
tofu plan  -var 'proxmox_endpoint=https://pve-home-01.lan:8006'
tofu apply -var 'proxmox_endpoint=https://pve-home-01.lan:8006'
# hypervisor_name defaults to the workspace name; override either var:
#   -var 'hypervisor_name=pve-home-01'
#   TF_VAR_proxmox_username="other@pve"
# If proxmox_endpoint is omitted it falls back to
# all.vars.proxmox_endpoints[hypervisor_name] in inventory.yaml.
```
