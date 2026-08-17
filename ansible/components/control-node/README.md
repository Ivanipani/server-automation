# Component: control-node (layer 0)

Prepares the machine that *drives* ansible — the user's laptop — not any
fleet host. Everything here is `connection: local`, so this is the one
component the ephemeral-VM integration harness cannot exercise; its
`tests/verify.yml` runs against the control node itself.

Run it once on a fresh checkout, before anything else:

```
just control-node
```

## Roles

| role | guarantees | unapply |
|---|---|---|
| `control-node-deps` | required CLIs, python packages under ansible's own interpreter, galaxy collections | n/a (read-only) |
| `control-node-ansible-key` | `~/.ssh/ansible` 0600 + `~/.ssh/ansible.pub` 0644 from the vault, so `ansible.cfg`'s `private_key_file` resolves | `control_node_ansible_key_enabled: false` removes both |
| `control-node-inventory-link` | `~/.ansible/inventory/inventory.yaml` → this checkout's `inventory.yaml` | `control_node_inventory_link_enabled: false` removes the symlink |

## Notes

- The keypair play is deliberately connection-local: `private_key_file`
  is ignored there, so it bootstraps cleanly when `~/.ssh/ansible` does
  not exist yet. It only needs the vault password.
- Re-run after rotating the keypair; it overwrites with the canonical
  vaulted value.
- `--tags deps` runs only the dependency check — that is what
  `just check` invokes, and why it is safe as a prerequisite of every
  other recipe.
