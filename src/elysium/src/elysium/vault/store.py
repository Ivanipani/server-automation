"""The ansible-vault half of the public API: `VaultStore` = a vault file +
the password that opens it, `VaultIndex` = every such file in the repo."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

from elysium.errors import ElysiumError
from elysium.vault.crypto import VaultCrypto
from elysium.vault.document import VaultDocument, VaultEntry


@dataclass(frozen=True)
class WriteResult:
    name: str
    path: Path
    replaced: bool

    @property
    def action(self) -> str:
        return "updated" if self.replaced else "added"


@dataclass(frozen=True)
class VaultStore:
    path: Path
    crypto: VaultCrypto

    @classmethod
    def from_repo(cls, repo, path: Path) -> VaultStore:
        return cls(path=path, crypto=VaultCrypto(password_file=repo.vault_password_file))

    def document(self) -> VaultDocument:
        return VaultDocument.load(self.path)

    def names(self) -> list[str]:
        return self.document().names()

    def entry(self, name: str) -> VaultEntry:
        return self.document().get(name)

    def get(self, name: str) -> str:
        """Decrypted value of `name`."""
        return self.crypto.decrypt(self.entry(name).ciphertext)

    def set(self, name: str, value: str, *, verify: bool = True) -> WriteResult:
        """Encrypt `value` and write it under `name`.

        An existing entry keeps its exact indentation, its position in the file,
        and every comment around it — only the ciphertext lines change. A new
        entry is appended using the indentation the file already uses.
        """
        document = self.document()
        existing = document.find(name)
        # Keep the entry on its current vault-id so re-encryption is a no-op for
        # anything keyed off the label.
        ciphertext = self.crypto.encrypt(value, vault_id=existing.vault_id if existing else None)
        replaced = document.set(name, ciphertext)
        document.save(self.path)

        if verify:
            roundtrip = VaultDocument.load(self.path).get(name)
            if self.crypto.decrypt(roundtrip.ciphertext) != value:
                raise ElysiumError(f"verification failed: `{name}` did not decrypt to the value written")
        return WriteResult(name=name, path=self.path, replaced=replaced)


@dataclass(frozen=True)
class VaultIndex:
    """Every vault file in play, opened by the same password.

    Variable names are unique within a file, never across the repo, so a lookup
    returns *all* the files holding a name and the caller disambiguates.
    """

    crypto: VaultCrypto
    stores: tuple[VaultStore, ...]

    @classmethod
    def from_repo(cls, repo, paths: Iterable[Path] | None = None) -> VaultIndex:
        """Index `paths`, or every vault file the repo can find."""
        found = repo.ansible_vault_files if paths is None else paths
        crypto = VaultCrypto(password_file=repo.vault_password_file)
        return cls(crypto, tuple(VaultStore(path=p.resolve(), crypto=crypto) for p in found))

    def entries(self) -> list[tuple[VaultStore, str]]:
        """`(file, variable)` for every vaulted variable, in file order."""
        return [(store, name) for store in self.stores for name in store.names()]

    def stores_with(self, name: str) -> list[VaultStore]:
        return [store for store in self.stores if store.document().find(name) is not None]

    def store(self, path: Path) -> VaultStore:
        target = path.resolve()
        found = next((store for store in self.stores if store.path == target), None)
        if found is None:
            raise ElysiumError(f"{path} is not one of the vault files in play")
        return found
