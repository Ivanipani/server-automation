"""`elysium` — a thin typer/rich shell over the library in `elysium.*`."""

from __future__ import annotations

import shutil
import sys
from importlib.metadata import PackageNotFoundError, version as pkg_version
from pathlib import Path
from typing import Annotated

import typer
from rich.table import Table

from elysium.catalog import Catalog
from elysium.cli import ansible_cmds, sops_cmds
from elysium.cli._common import emit_secret, err, state
from elysium.errors import Cancelled, ElysiumError
from elysium.fzf import pick
from elysium.repo import SECRETS_DIRNAME

app = typer.Typer(
    no_args_is_help=True,
    add_completion=False,
    pretty_exceptions_enable=False,
    help="Encrypt and decrypt poochella secrets — ansible-vault and SOPS, one tool.",
)
app.add_typer(ansible_cmds.app, name="ansible")
app.add_typer(sops_cmds.app, name="sops")


@app.callback()
def global_options(
    repo_root: Annotated[
        Path | None,
        typer.Option("--repo-root", "-C", help="Repo root [default: discovered from cwd]"),
    ] = None,
) -> None:
    state.set_root(repo_root)


@app.command()
def get(
    query: Annotated[str | None, typer.Argument(help="Prefill the picker with this query")] = None,
) -> None:
    """Fuzzy-find any secret — ansible-vault or SOPS — and decrypt it to stdout.

    Each row is the key plus the file holding it, so the picker doubles as an
    answer to "where does this secret live?".
    """
    catalog = Catalog(state.repo)
    rows = catalog.rows()
    selection = pick(rows, prompt="secret> ", header=f"key / file — under {state.repo.root}", query=query)
    emit_secret(catalog.get(rows[selection]))


@app.command()
def doctor() -> None:
    """Report where the keys, secret stores and tools resolved from."""
    table = Table(title="elysium doctor", title_style="bold", header_style="dim")
    table.add_column("check")
    table.add_column("status")
    table.add_column("detail", overflow="fold")

    def row(name: str, ok: bool, detail: str) -> None:
        table.add_row(name, "[green]ok[/green]" if ok else "[red]missing[/red]", detail)

    try:
        repo = state.repo
    except ElysiumError as exc:
        err.print(f"[red]{exc}[/red]")
        raise typer.Exit(1) from exc

    row("repo root", True, str(repo.root))
    row(f"{SECRETS_DIRNAME}/", repo.secrets_dir.is_dir(), str(repo.secrets_dir))

    for label, resolve in (
        ("ansible-vault password", lambda: repo.vault_password_file),
        ("sops age key", lambda: repo.age_key_file),
    ):
        try:
            path = resolve()
        except ElysiumError as exc:
            row(label, False, str(exc))
            continue
        row(label, True, repo.relative(path))

    vault_files = repo.ansible_vault_files
    row("vault files", bool(vault_files), ", ".join(repo.relative(p) for p in vault_files) or "none found")
    row("sops files", True, f"{len(repo.sops_files())} found")
    for tool in ("ansible-vault", "sops", "fzf"):
        found = shutil.which(tool)
        row(tool, bool(found), found or "not on PATH")

    err.print(table)


@app.command()
def version() -> None:
    """Print the elysium version."""
    try:
        emit_secret(pkg_version("elysium"))
    except PackageNotFoundError:
        emit_secret("0.0.0+dev")


def main() -> None:
    try:
        app()
    except Cancelled:
        sys.exit(130)
    except (ElysiumError, OSError) as exc:
        err.print(f"[red]error:[/red] {exc}")
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
