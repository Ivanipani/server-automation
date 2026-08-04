"""`elysium sops …` — SOPS-encrypted manifests under k8s/, a whole file at a time."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from elysium.cli._common import confirm, emit_secret, err, out, read_text, resolve_path, state
from elysium.errors import ElysiumError
from elysium.fzf import pick
from elysium.sops import SopsStore

app = typer.Typer(no_args_is_help=True, help="SOPS-encrypted manifests (*.sops.yaml), whole-file")

FileArg = Annotated[Path | None, typer.Argument(help="*.sops.yaml path; fzf-picked if omitted")]


def _store() -> SopsStore:
    return SopsStore.from_repo(state.repo)


def _select_file(path: Path | None, *, must_exist: bool = True) -> Path:
    if path is not None:
        resolved = resolve_path(path)
        if must_exist and not resolved.is_file():
            raise ElysiumError(f"no such file: {path}")
        return resolved
    repo = state.repo
    files = repo.sops_files()
    if not files:
        raise ElysiumError(f"no *.sops.yaml files under {repo.root}")
    return repo.root / pick([repo.relative(f) for f in files], prompt="sops> ")


@app.command("list")
def list_files() -> None:
    """List every SOPS-encrypted file in the repo."""
    repo = state.repo
    files = repo.sops_files()
    if out.is_terminal:
        err.print(f"[dim]{repo.root} — {len(files)} files[/dim]")
    for path in files:
        emit_secret(repo.relative(path))


@app.command("get")
def get_file(file: FileArg = None) -> None:
    """Decrypt a whole manifest to stdout."""
    emit_secret(_store().decrypt(_select_file(file)))


@app.command("set")
def set_file(
    file: FileArg = None,
    from_file: Annotated[
        Path | None, typer.Option("--from-file", "-f", help="Read the plaintext manifest from a file")
    ] = None,
    stdin: Annotated[bool, typer.Option("--stdin", help="Read the plaintext manifest from stdin")] = False,
    yes: Annotated[bool, typer.Option("--yes", "-y", help="Skip the overwrite confirmation")] = False,
) -> None:
    """Replace a whole manifest with plaintext YAML, re-encrypted.

    Creates the file if it does not exist. Use `edit` for an interactive
    round-trip instead.
    """
    if from_file is None and not stdin:
        raise ElysiumError("give --stdin or --from-file (or use `elysium sops edit` for $EDITOR)")

    path = _select_file(file, must_exist=False)
    store = _store()
    if path.is_file() and not yes and not confirm(f"Overwrite {state.repo.relative(path)}?", default=True):
        raise typer.Exit(1)

    existed = store.write(path, read_text(from_file=from_file, stdin=stdin))
    action = "updated" if existed else "created"
    err.print(f"[green]{action}[/green] {state.repo.relative(path)}")


@app.command("edit")
def edit_file(file: FileArg = None) -> None:
    """Open a manifest decrypted in $EDITOR; re-encrypts on save."""
    _store().edit(_select_file(file))


@app.command("encrypt")
def encrypt_file(file: FileArg = None) -> None:
    """Encrypt a plaintext manifest in place, per the nearest .sops.yaml rules."""
    store = _store()
    path = _select_file(file)
    if store.file(path).is_encrypted():
        err.print(f"[yellow]{state.repo.relative(path)} is already encrypted[/yellow]")
        raise typer.Exit(0)
    store.encrypt_in_place(path)
    err.print(f"[green]encrypted[/green] {state.repo.relative(path)}")
