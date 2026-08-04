"""Repo layout discovery.

Convention: **all encryption key material lives in `<repo-root>/secrets/`** —
`secrets/ansible-pass` (ansible-vault password) and `secrets/age.agekey` (the
SOPS age identity). `elysium doctor` reports what resolved.

The secret *stores* are the opposite: found by content, anywhere in the tree, so
no filename or directory layout is prescribed.
"""

from __future__ import annotations

import os
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

from elysium.errors import RepoNotFound, SecretKeyNotFound
from elysium.vault.document import holds_vault_entries

SECRETS_DIRNAME = "secrets"
_ROOT_MARKERS = (".jj", ".git")
_PRUNED_DIRS = {".git", ".jj", ".venv", "node_modules", "dist", ".pants.d", ".mypy_cache"}

_VAULT_PASSWORD_GLOBS = ("ansible-pass", "*ansible-pass*", "vault-pass*", "ansible-vault-pass*")
_AGE_KEY_GLOBS = ("age.agekey", "*.agekey", "age.key")

_YAML_SUFFIXES = (".yml", ".yaml")
_SOPS_GLOBS = ("*.sops.yaml", "*.sops.yml")


@dataclass(frozen=True)
class Repo:
    """The repository the secrets belong to."""

    root: Path

    @classmethod
    def discover(cls, start: Path | None = None) -> Repo:
        override = os.environ.get("ELYSIUM_REPO_ROOT")
        if override:
            return cls(Path(override).expanduser().resolve())
        here = (start or Path.cwd()).resolve()
        for candidate in (here, *here.parents):
            if any((candidate / marker).exists() for marker in _ROOT_MARKERS):
                return cls(candidate)
        raise RepoNotFound(f"no repository root (.jj/.git) at or above {here}")

    @property
    def secrets_dir(self) -> Path:
        return self.root / SECRETS_DIRNAME

    def _resolve_key(self, *, env_var: str, globs: Iterable[str], description: str) -> Path:
        for candidate in self._key_candidates(env_var=env_var, globs=globs):
            if candidate.is_file():
                return candidate
        raise SecretKeyNotFound(
            f"{description} not found (looked in {self.secrets_dir}; override with ${env_var})"
        )

    def _key_candidates(self, *, env_var: str, globs: Iterable[str]) -> Iterator[Path]:
        override = os.environ.get(env_var)
        if override:
            yield Path(override).expanduser()
            return
        for pattern in globs:
            yield from sorted(self.secrets_dir.glob(pattern))

    @cached_property
    def vault_password_file(self) -> Path:
        return self._resolve_key(
            env_var="ELYSIUM_VAULT_PASSWORD_FILE",
            globs=_VAULT_PASSWORD_GLOBS,
            description="ansible-vault password file",
        )

    @cached_property
    def age_key_file(self) -> Path:
        return self._resolve_key(
            env_var="SOPS_AGE_KEY_FILE",
            globs=_AGE_KEY_GLOBS,
            description="SOPS age key file",
        )

    def _walk(self) -> Iterator[Path]:
        """Every non-hidden file in the repo, minus the pruned directories."""
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = [d for d in dirnames if d not in _PRUNED_DIRS]
            base = Path(dirpath)
            for name in filenames:
                if not name.startswith("."):
                    yield base / name

    @cached_property
    def ansible_vault_files(self) -> list[Path]:
        """Every YAML file in the repo carrying at least one `!vault` variable.

        Found by content, so any number of files anywhere may hold vaulted
        variables — `ansible/group_vars/all/vault.yml` is a convention, not a
        constraint.
        """
        return sorted(
            p for p in self._walk() if p.suffix in _YAML_SUFFIXES and holds_vault_entries(p)
        )

    def sops_files(self) -> list[Path]:
        """Every `*.sops.yaml` in the repo (the `.sops.yaml` config is not one)."""
        return sorted(p for p in self._walk() if any(p.match(g) for g in _SOPS_GLOBS))

    def relative(self, path: Path) -> str:
        try:
            return str(path.resolve().relative_to(self.root))
        except ValueError:
            return str(path)
