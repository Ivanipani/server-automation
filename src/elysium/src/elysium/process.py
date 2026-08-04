"""Thin subprocess helpers.

Secrets are passed to child processes over stdin, never argv — argv is visible
in `ps` to every user on the box.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from collections.abc import Mapping, Sequence
from pathlib import Path

from elysium.errors import CommandFailed, ToolNotFound


def require(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise ToolNotFound(f"`{name}` not found on PATH")
    return path


def run(
    argv: Sequence[str],
    *,
    stdin: str | bytes | None = None,
    env: Mapping[str, str] | None = None,
    cwd: Path | None = None,
) -> str:
    """Run `argv`, feed `stdin`, return stdout. Raises `CommandFailed` on nonzero."""
    argv = [str(a) for a in argv]
    require(argv[0])
    payload = stdin.encode() if isinstance(stdin, str) else stdin
    proc = subprocess.run(
        argv,
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd,
        env={**os.environ, **env} if env else None,
    )
    if proc.returncode != 0:
        raise CommandFailed(argv, proc.returncode, proc.stderr.decode(errors="replace"))
    return proc.stdout.decode()


def run_interactive(
    argv: Sequence[str],
    *,
    env: Mapping[str, str] | None = None,
    cwd: Path | None = None,
) -> None:
    """Run `argv` attached to the terminal (editors, `sops` in edit mode)."""
    argv = [str(a) for a in argv]
    require(argv[0])
    proc = subprocess.run(argv, cwd=cwd, env={**os.environ, **env} if env else None)
    if proc.returncode != 0:
        raise CommandFailed(argv, proc.returncode, "")
