# elysium

One tool for every secret in this repo — **ansible-vault** variables in any
YAML file and **SOPS**-encrypted manifests. Replaces the
`secret-encrypt` / `secret-decrypt` recipes in the root `justfile` and the
`edit-secret` / `encrypt-sops` recipes in `k8s/justfile`.

All behaviour lives in the library (`elysium.*`); `elysium.cli` is a thin
typer/rich wrapper over it.

## Install

```sh
uv tool install --editable src/elysium     # `elysium` on PATH, tracks the checkout
uv run --project src/elysium elysium ...   # or run it without installing

pants run src/elysium:elysium -- ...       # or through the build graph
pants package src/elysium:elysium          # -> dist/src.elysium/elysium.pex
```

The `pex_binary` is a self-contained zipapp: `./dist/src.elysium/elysium.pex`
runs anywhere with a 3.12 interpreter, no venv. It still shells out to
`ansible-vault`, `sops` and `fzf`, which must be on `$PATH`. The full address is
required — bare `src/elysium` is ambiguous with the requirement targets the
`pyproject.toml` generates.

## Conventions

Key material is looked up in **`<repo-root>/secrets/`**:

| what | `secrets/` name | env override |
| --- | --- | --- |
| ansible-vault password | `ansible-pass` | `ELYSIUM_VAULT_PASSWORD_FILE` |
| SOPS age identity | `age.agekey` | `SOPS_AGE_KEY_FILE` |

`elysium doctor` says what resolved. The repo root is found by walking up
for `.jj`/`.git` (override with `-C` or `$ELYSIUM_REPO_ROOT`).

**Secret stores are found by content, not by path.** Every `*.yml`/`*.yaml` in
the repo carrying at least one `name: !vault |` entry is a vault file, and every
`*.sops.yaml` is a SOPS file — so any number of them, anywhere in the tree, are
in play. `ansible/group_vars/all/vault.yml` is where this repo happens to keep
its variables, not a rule the tool enforces. `--vault-file` scopes a command to
one file.

Anything not given as an argument is **fzf-picked**. Decrypted values go to
**stdout raw**; status messages go to stderr — so `elysium ansible get X | pbcopy`
is exactly the secret and nothing else.

## Commands

```sh
elysium doctor                    # where keys, stores and tools resolved from
elysium get [QUERY]               # fzf across ansible + SOPS, decrypt the pick

elysium ansible list                  # every variable, in every vault file
elysium ansible get [NAME]            # --vault-file F to scope to one file
elysium ansible set [NAME] [VALUE]    # --stdin | --from-file F | prompts
elysium ansible encrypt NAME [VALUE]  # print a pasteable `name: !vault |` block

elysium sops list                     # every *.sops.yaml in the repo
elysium sops get  [FILE]              # decrypt the whole manifest to stdout
elysium sops set  [FILE]              # replace the whole manifest; --stdin | --from-file F
elysium sops edit [FILE]              # $EDITOR, re-encrypts on save
elysium sops encrypt [FILE]           # encrypt a plaintext manifest in place
```

**The two stores differ in granularity, on purpose.** ansible-vault addresses a
*variable*; SOPS addresses a *whole manifest*. There is no per-key SOPS API —
`get` hands you the entire decrypted file and `set` takes an entire file back.
Round-tripping is just a pipe:

```sh
elysium sops get k8s/infra/storage/controllers/longhorn/basic-auth.sops.yaml \
  | edit-somehow | elysium sops set k8s/infra/.../basic-auth.sops.yaml --stdin
```

`elysium get` indexes both stores into one picker (`elysium.catalog`). Each row
is the secret's name, padded into a column, followed by **the file that holds
it** — so it also answers "where does this secret live?". Picking an ansible row
decrypts that variable; picking a SOPS row decrypts that whole manifest. Paths
are repo-relative; the root is in the fzf header.

```
vault_postgres_pass                     ansible/group_vars/all/vault.yml
basic-auth                              k8s/infra/storage/controllers/longhorn/basic-auth.sops.yaml
```

## Writes

Both `set` commands write atomically (temp file + rename, permissions
preserved) and verify by decrypting the result back before reporting success.
Secret values reach `ansible-vault` / `sops` on **stdin**, never argv, so they
never appear in `ps`.

`elysium ansible set` rewrites **one variable** and leaves the rest of the file
byte-identical. It treats the vault file as lines of text, never as YAML: an
existing variable keeps its exact indentation, its position in the file, its
`$ANSIBLE_VAULT;1.2;…;<vault-id>` label and every comment around it — only its
ciphertext lines are replaced. A new variable is appended using the indentation
the file already uses.

A name is unique within a file, never across the repo, so `get`/`set` resolve it
against every vault file: one match is used, several are fzf-disambiguated, and
a name that matches nothing goes to the repo's only vault file (or to one you
pick). `--vault-file` short-circuits all of that.

`elysium sops set` replaces **the whole manifest**, creating it if absent.
Encrypting means the plaintext must exist on disk for a moment, so it is written
to a `0600` sibling temp file (still named `*.sops.yaml`, so the config's
`path_regex` matches), encrypted there, verified, and only then renamed over the
target — plaintext never appears at the real path, and a failure anywhere leaves
the original untouched.

> `sops` resolves `.sops.yaml` relative to the **current working directory**,
> not to the file it is encrypting (this is why the `k8s/justfile` recipes have
> to `cd` first). Every elysium invocation passes an explicit `--config` found by
> walking up from the target, so the commands work from any directory.

## Library

```python
from elysium import Catalog, Repo, SopsStore, VaultIndex

repo = Repo.discover()
repo.ansible_vault_files                                     # every file holding !vault entries
index = VaultIndex.from_repo(repo)
index.entries()                                              # [(VaultStore, variable name), …]
index.stores_with("vault_postgres_pass")[0].set("…", "hunter2")   # one variable
SopsStore.from_repo(repo).write(path, manifest_text)         # one whole manifest
Catalog(repo).rows()                                         # picker rows -> SecretRef
```

## Tests

```sh
uv run --project src/elysium pytest
```
