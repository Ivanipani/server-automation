"""Typer wrapper over the library. Business logic belongs in `elysium.*`.

The root app lives in `elysium.cli.root`, not `elysium.cli.main` — a module
named `main` would be shadowed by the `main` entry point re-exported here.
"""

from elysium.cli.root import app, main

__all__ = ["app", "main"]
