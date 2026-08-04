"""`elysium ansible …` — ansible-vault variables, across every vault file."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from elysium.catalog import SecretRef, picker_rows
from elysium.cli._common import confirm, emit_secret, err, out, read_value, resolve_path, state
from elysium.errors import ElysiumError, EntryNotFound
from elysium.fzf import pick
from elysium.vault import VaultCrypto, VaultIndex, VaultStore, yaml_block

app = typer.Typer(no_args_is_help=True, help="ansible-vault variables in any group_vars file")

VaultFile = Annotated[
    Path | None,
    typer.Option("--vault-file", help="Restrict to one vault YAML [default: every one in the repo]"),
]


def _index(vault_file: Path | None) -> VaultIndex:
    """Every vault file in the repo, or just the one asked for."""
    paths = [resolve_path(vault_file)] if vault_file else None
    return VaultIndex.from_repo(state.repo, paths)


def _pick_store(stores: list[VaultStore], header: str) -> VaultStore:
    rows = {state.repo.relative(store.path): store for store in stores}
    return rows[pick(rows, prompt="file> ", header=header)]


def _resolve(index: VaultIndex, name: str | None, *, allow_new: bool = False) -> tuple[VaultStore, str]:
    """Settle on the one `(file, variable)` pair to act on.

    A name can live in several files — nothing makes it repo-unique — so an
    ambiguous name is disambiguated by a second pick rather than guessed at.
    """
    if name is None:
        rows = picker_rows(state.repo, [SecretRef("ansible", s.path, n) for s, n in index.entries()])
        selection = pick(rows, prompt="vault> ", header="variable / file", allow_new=allow_new)
        ref = rows.get(selection)
        if ref is not None:
            return index.store(ref.path), str(ref.key)
        name = selection.strip()  # typed a name that matched nothing

    matches = index.stores_with(name)
    if len(matches) == 1:
        return matches[0], name
    if matches:
        return _pick_store(matches, f"`{name}` is in {len(matches)} files"), name
    if not allow_new:
        raise EntryNotFound(f"no vaulted variable `{name}` in {_where(index)}")
    return _new_home(index, name), name


def _new_home(index: VaultIndex, name: str) -> VaultStore:
    """Which file a brand-new variable is written to."""
    if not index.stores:
        raise ElysiumError(f"no ansible-vault files under {state.repo.root} — pass --vault-file")
    if len(index.stores) == 1:
        return index.stores[0]
    return _pick_store(list(index.stores), f"where should `{name}` go?")


def _where(index: VaultIndex) -> str:
    if len(index.stores) == 1:
        return state.repo.relative(index.stores[0].path)
    return f"any of the {len(index.stores)} vault files under {state.repo.root}"


@app.command("list")
def list_vars(vault_file: VaultFile = None) -> None:
    """List every vaulted variable name, in every vault file."""
    for store in _index(vault_file).stores:
        names = store.names()
        if out.is_terminal:
            err.print(f"[dim]{state.repo.relative(store.path)} — {len(names)} variables[/dim]")
        for name in names:
            emit_secret(name)


@app.command("get")
def get_var(
    name: Annotated[str | None, typer.Argument(help="Variable name; fzf-picked if omitted")] = None,
    vault_file: VaultFile = None,
) -> None:
    """Decrypt one variable to stdout."""
    store, name = _resolve(_index(vault_file), name)
    emit_secret(store.get(name))


@app.command("set")
def set_var(
    name: Annotated[str | None, typer.Argument(help="Variable name; fzf-picked if omitted")] = None,
    value: Annotated[str | None, typer.Argument(help="Value; prompted for if omitted")] = None,
    from_file: Annotated[Path | None, typer.Option("--from-file", "-f", help="Read the value from a file")] = None,
    stdin: Annotated[bool, typer.Option("--stdin", help="Read the value from stdin")] = False,
    vault_file: VaultFile = None,
    verify: Annotated[bool, typer.Option(help="Decrypt the result and compare")] = True,
    yes: Annotated[bool, typer.Option("--yes", "-y", help="Skip the overwrite confirmation")] = False,
) -> None:
    """Encrypt a value into a vault file, in place.

    An existing variable keeps its exact indentation, position and surrounding
    comments — only its ciphertext lines are rewritten. A new variable goes to
    the repo's only vault file, or to one you pick.
    """
    store, name = _resolve(_index(vault_file), name, allow_new=True)
    existing = store.document().find(name)
    if existing is not None and not yes and not confirm(f"Overwrite `{name}`?", default=True):
        raise typer.Exit(1)

    result = store.set(name, read_value(value, from_file=from_file, stdin=stdin, label=name), verify=verify)
    err.print(f"[green]{result.action}[/green] [bold]{result.name}[/bold] in {state.repo.relative(result.path)}")


@app.command("encrypt")
def encrypt_var(
    name: Annotated[str, typer.Argument(help="Variable name for the YAML block")],
    value: Annotated[str | None, typer.Argument(help="Value; prompted for if omitted")] = None,
    from_file: Annotated[Path | None, typer.Option("--from-file", "-f", help="Read the value from a file")] = None,
    stdin: Annotated[bool, typer.Option("--stdin", help="Read the value from stdin")] = False,
) -> None:
    """Print a pasteable `name: !vault |` block without touching any file.

    (What `just secret-encrypt` did.)
    """
    crypto = VaultCrypto(password_file=state.repo.vault_password_file)  # no file involved
    plaintext = read_value(value, from_file=from_file, stdin=stdin, label=name)
    emit_secret(yaml_block(name, crypto.encrypt(plaintext)))
