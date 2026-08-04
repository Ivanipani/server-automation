"""elysium — one-stop secret management for the poochella repo.

All business logic lives here; `elysium.cli` is a thin typer wrapper over it.

    from elysium import Repo, SopsStore, VaultIndex

    repo = Repo.discover()
    index = VaultIndex.from_repo(repo)                    # every vault file in the repo
    index.stores_with("vault_postgres_pass")[0].set(...)  # one variable
    SopsStore.from_repo(repo).write(path, text)           # one whole manifest
"""

from elysium.catalog import Catalog, SecretRef
from elysium.errors import (
    Cancelled,
    CommandFailed,
    ElysiumError,
    EntryNotFound,
    RepoNotFound,
    SecretKeyNotFound,
    ToolNotFound,
)
from elysium.repo import Repo
from elysium.sops import SopsFile, SopsStore
from elysium.vault import (
    VaultCrypto,
    VaultDocument,
    VaultEntry,
    VaultIndex,
    VaultStore,
    yaml_block,
)

__all__ = [
    "Cancelled",
    "Catalog",
    "CommandFailed",
    "ElysiumError",
    "EntryNotFound",
    "Repo",
    "RepoNotFound",
    "SecretKeyNotFound",
    "SecretRef",
    "SopsFile",
    "SopsStore",
    "ToolNotFound",
    "VaultCrypto",
    "VaultDocument",
    "VaultEntry",
    "VaultIndex",
    "VaultStore",
    "yaml_block",
]
