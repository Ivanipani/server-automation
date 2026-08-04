"""Exception hierarchy. Everything the CLI is expected to survive derives from
`ElysiumError`; the CLI turns those into a one-line stderr message + exit 1."""

from __future__ import annotations


class ElysiumError(Exception):
    """Base class for expected, user-facing failures."""


class RepoNotFound(ElysiumError):
    pass


class ToolNotFound(ElysiumError):
    pass


class SecretKeyNotFound(ElysiumError):
    """The encryption key material (vault password / age key) is missing."""


class CommandFailed(ElysiumError):
    def __init__(self, argv: list[str], returncode: int, stderr: str) -> None:
        self.argv = argv
        self.returncode = returncode
        self.stderr = stderr.strip()
        detail = f": {self.stderr}" if self.stderr else ""
        super().__init__(f"`{argv[0]}` exited {returncode}{detail}")


class EntryNotFound(ElysiumError):
    pass


class Cancelled(ElysiumError):
    """User aborted an interactive picker/prompt. Exits 130, silently."""
