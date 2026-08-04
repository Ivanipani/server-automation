"""Shared CLI plumbing: where the repo came from, how secrets leave the process.

**Secret values go to stdout raw; everything decorative goes to stderr.** That
keeps `elysium ansible get X | pbcopy` honest.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

import typer
from rich.console import Console

from elysium.errors import Cancelled, ElysiumError
from elysium.repo import Repo

err = Console(stderr=True)
out = Console()


@dataclass
class State:
    _repo_root: Path | None = None
    _repo: Repo | None = field(default=None, init=False)

    @property
    def repo(self) -> Repo:
        if self._repo is None:
            self._repo = Repo.discover(self._repo_root)
        return self._repo

    def set_root(self, root: Path | None) -> None:
        self._repo_root = root
        self._repo = None


state = State()


def resolve_path(path: Path) -> Path:
    """Accept paths relative to the cwd *or* to the repo root — the latter is
    what every `elysium … list` prints, so it must work from any directory."""
    if path.is_absolute() or path.exists():
        return path
    from_root = state.repo.root / path
    return from_root if from_root.exists() else path


def emit_secret(value: str) -> None:
    """Write a decrypted value to stdout verbatim — no rich markup, no styling."""
    sys.stdout.write(value)
    if not value.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()


def read_text(*, from_file: Path | None, stdin: bool) -> str:
    """Read a whole document from --from-file or --stdin."""
    if from_file is not None:
        return from_file.read_text()
    if stdin:
        return sys.stdin.read()
    raise ElysiumError("no input source given (--stdin or --from-file)")


def read_value(value: str | None, *, from_file: Path | None, stdin: bool, label: str) -> str:
    """Resolve a secret value from --from-file / --stdin / argument / prompt."""
    if from_file is not None or stdin:
        return read_text(from_file=from_file, stdin=stdin)
    if value is not None:
        return value
    try:
        return typer.prompt(f"Value for {label}", hide_input=True, confirmation_prompt=True)
    except (typer.Abort, EOFError) as exc:
        raise Cancelled("no value entered") from exc


def confirm(question: str, *, default: bool = False) -> bool:
    try:
        return typer.confirm(question, default=default, err=True)
    except typer.Abort as exc:
        raise Cancelled("aborted") from exc
