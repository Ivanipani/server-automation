"""fzf wrapper. Every interactive selection in the CLI funnels through here."""

from __future__ import annotations

import subprocess
from collections.abc import Iterable

from elysium.errors import Cancelled, ElysiumError
from elysium.process import require

_FZF_EXIT_NO_MATCH = 1
_FZF_EXIT_INTERRUPT = 130


def pick(
    items: Iterable[str],
    *,
    prompt: str = "> ",
    header: str | None = None,
    allow_new: bool = False,
    query: str | None = None,
) -> str:
    """Fuzzy-pick one of `items`.

    With `allow_new`, a typed query that matches nothing is returned verbatim
    (used by `set`, where the name may not exist yet). Raises `Cancelled` on
    escape/ctrl-c.
    """
    choices = list(dict.fromkeys(items))
    if not choices and not allow_new:
        raise ElysiumError("nothing to choose from")

    argv = [
        require("fzf"),
        f"--prompt={prompt}",
        "--height=40%",
        "--reverse",
        "--no-multi",
    ]
    if header:
        argv.append(f"--header={header}")
    if allow_new:
        argv.append("--print-query")
    if query:
        argv.append(f"--query={query}")

    proc = subprocess.run(
        argv,
        input="\n".join(choices).encode(),
        stdout=subprocess.PIPE,
    )
    lines = proc.stdout.decode().splitlines()

    if (
        proc.returncode == _FZF_EXIT_INTERRUPT
        or (proc.returncode != 0 and not allow_new)
        or (allow_new and proc.returncode not in (0, _FZF_EXIT_NO_MATCH))
    ):
        raise Cancelled("selection cancelled")

    # --print-query prepends the query; the selection (if any) is the last line.
    selected = lines[-1].strip() if lines else ""
    if not selected:
        raise Cancelled("nothing selected")
    return selected
