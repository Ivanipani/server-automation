"""A single flat index over both secret stores.

`elysium get` is the one-stop entry point, so the two stores have to look alike:
one row per secret, each naming the file that holds it. The stores differ in
granularity — ansible-vault addresses a *variable*, SOPS addresses a *whole
manifest* — so an ansible row decrypts one value and a SOPS row decrypts the
entire file.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from elysium.repo import Repo
from elysium.sops import SopsStore
from elysium.vault import VaultIndex, VaultStore

Store = Literal["ansible", "sops"]

_NAME_COLUMN_CAP = 44
_SOPS_SUFFIXES = (".sops.yaml", ".sops.yml")


@dataclass(frozen=True)
class SecretRef:
    """Where one secret lives. `key` is the vault variable for ansible refs and
    None for SOPS refs, which address the whole file."""

    store: Store
    path: Path
    key: str | None = None

    @property
    def name(self) -> str:
        if self.key is not None:
            return self.key
        name = self.path.name
        for suffix in _SOPS_SUFFIXES:
            if name.endswith(suffix):
                return name[: -len(suffix)]
        return name


def picker_rows(repo: Repo, refs: Sequence[SecretRef]) -> dict[str, SecretRef]:
    """Picker rows -> ref. Name first (that's what you type), then the file
    holding it, padded into a column."""
    width = min(max((len(ref.name) for ref in refs), default=0), _NAME_COLUMN_CAP)
    return {f"{ref.name:<{width}}  {repo.relative(ref.path)}": ref for ref in refs}


@dataclass(frozen=True)
class Catalog:
    repo: Repo

    def refs(self) -> list[SecretRef]:
        return list(self._iter_refs())

    def _iter_refs(self) -> Iterator[SecretRef]:
        for store, name in VaultIndex.from_repo(self.repo).entries():
            yield SecretRef("ansible", store.path, name)
        for path in self.repo.sops_files():
            yield SecretRef("sops", path)

    def get(self, ref: SecretRef) -> str:
        if ref.store == "ansible":
            return VaultStore.from_repo(self.repo, ref.path).get(str(ref.key))
        return SopsStore.from_repo(self.repo).decrypt(ref.path)

    def rows(self, refs: list[SecretRef] | None = None) -> dict[str, SecretRef]:
        return picker_rows(self.repo, self.refs() if refs is None else refs)
