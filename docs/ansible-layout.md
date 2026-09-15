# Ansible layout: components, layers, deployments

Status: **in migration.** `ansible/components/` is the target shape;
`ansible/playbooks/poochella/` is the legacy tier tree, shrinking one
component at a time. Both work today.

## Why

The tier tree under `playbooks/poochella/infra/` mixes three concerns in
one file set: *what a thing is* (install node_exporter), *where it goes*
(the `physical` group), and *when it runs* (ordinal prefix, one global
critical path). That makes a step un-reusable outside poochella and
un-testable in isolation — the smallest unit you can exercise is a tier,
and a tier only makes sense mid-way through a cluster build.

Splitting those three concerns gives:

| concern | lives in | reusable? |
|---|---|---|
| behaviour | `components/<name>/roles/<role>/` | yes — any host, any cluster |
| composition | `components/<name>/site.yml` | yes — parameterised by host var |
| targeting + order | deployment (`playbooks/poochella/…site.yml`) | no, and that's fine |

## Layers

A component may only depend on components in a strictly lower layer.
`component.yml` declares this so the future test harness knows what to
pre-apply to the ephemeral VM.

```
L0  control-node      localhost prerequisites (keys, inventory link, tool deps)
L1  os-baseline       any Linux: users, apt hygiene, ssh-hardening, firewall, motd
L2  host-hardware     baremetal only: disks, nfs mounts, nic-offload, firmware, bridges
L2  remote-access     tailscale
L2  observability     node-exporter
L3  hypervisor        Proxmox VE fabric
L3  nas               Synology DSM
L3  router            OPNsense
L4  bootserv          netboot + artifact publishing (needs hypervisor + os-baseline)
L4  kube              k3s, longhorn host prep, flux bootstrap
L5  workstation       dev users, dotfiles, tooling
```

The layer numbers are advisory ordering, not ordinals in a filename —
two components on the same layer are independent and may run in any
order or concurrently.

## Component contract

```
components/<name>/
  component.yml     metadata: layer, depends_on, default target
  site.yml          the ONLY entrypoint; plays map hosts → roles, zero task logic
  README.md         what it guarantees, knobs, how to apply/unapply
  roles/<role>/     behaviour, one role per independently-toggleable unit
  tests/verify.yml  assert-only smoke tests (no mutation)
```

Rules:

1. **`site.yml` contains no tasks.** Only `hosts:` + `roles:`. Anything
   you are tempted to write inline is a role, or a `tasks/` file inside
   one.
2. **Never hardcode a group.** Target
   `"{{ <name>_hosts | default('<sane default>') }}"` so one component
   can be pointed at a test VM, a single host, or a whole group without
   editing it. (The legacy tiers use a single shared `target_hosts` for
   this; per-component vars are what let several components co-exist in
   one run.)
3. **Every role has `<role>_enabled` (default `true`) and both sides of
   the block** — enabled installs, disabled unapplies. This is the
   existing repo guideline; components make it load-bearing, because
   `apply → verify → unapply → verify-absent → destroy` is the
   integration test.
4. **Every role has `meta/argument_specs.yml`.** It validates inputs at
   play start and doubles as the component's API doc.
5. **Role names are globally unique** across the monorepo — `roles_path`
   is a flat search path, so two components with a same-named role would
   silently shadow each other. Prefix with the component name when the
   role's name is generic.
6. **A role never reads inventory topology** (`hostvars`, group
   membership, `groups[...]`). That is deployment knowledge; pass it in
   as a parameter from the deployment layer.

Registering a new component means adding its `roles/` dir to
`roles_path` in `ansible/ansible.cfg`.

## Deployment layer

`playbooks/poochella/**/site.yml` is where poochella-specific facts
live: which groups get which component, in what order, with what
overrides. Post-migration a deployment file is nothing but:

```yaml
- import_playbook: ../../components/os-baseline/site.yml
  vars:
    os_baseline_hosts: physical
```

## Integration tests (planned)

Per component, driven by `component.yml`:

1. create an ephemeral VM from the bootserv01-published Debian qcow2
2. apply every `depends_on` component's `site.yml`
3. apply this component's `site.yml`
4. run `tests/verify.yml` — assert-only
5. re-apply with `<role>_enabled: false`, run `tests/verify-absent.yml`
6. destroy the VM

Small components are the point: step 2 is the cost, and it is bounded by
how deep the layer stack is, not by how big the cluster is.

## Migration order

Bottom-up, one component per change, legacy tier deleted as it lands:

1. ~~`control-node`~~ ✅ done — `components/control-node/`
2. ~~`router`~~ ✅ done — `components/router/`, invoked via the
   deployment wrapper `playbooks/poochella/infra/10-router.yml`
3. ~~`os-baseline`~~ ✅ done — `components/os-baseline/`, invoked via
   the deployment wrapper `playbooks/poochella/infra/14-os-baseline.yml`.
   `firewall-basic` and `motd` stayed shared top-level roles
   (`ansible/roles/`) rather than moving in — `30-guests`/`40-kube`
   consume them too.
4. ~~`host-hardware`, `remote-access`, `observability`~~ ✅ done — split
   out of the old `17-host` tier into `components/host-hardware/`,
   `components/remote-access/`, `components/observability/`, invoked
   via `playbooks/poochella/infra/{15-host-hardware,16-remote-access,
   17-observability}.yml`. `nfs-mounts` (extracted from the old
   `17-host/16-nfs-mounts.yml`) became a shared top-level role — the
   `30-guests` tier mounts NFS onto `kube_control_plane` VMs with it too.
5. ~~`nas`~~ ✅ done — `components/nas/`, invoked via the deployment
   wrapper `playbooks/poochella/infra/12-nas.yml`
6. `hypervisor`
7. `bootserv` — needs the heavy `infra/tasks/*.yml` bake/publish logic
   pulled into roles first
8. `kube`
