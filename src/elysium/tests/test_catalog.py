"""Picker rows carry the file each secret lives in, and map back to their ref."""

from __future__ import annotations

from pathlib import Path

import pytest

from elysium.catalog import Catalog, SecretRef
from elysium.repo import Repo

ROOT = Path("/repo")
REFS = [
    SecretRef("ansible", ROOT / "ansible/group_vars/all/vault.yml", "vault_postgres_pass"),
    SecretRef("ansible", ROOT / "ansible/group_vars/all/vault.yml", "vault_a"),
    SecretRef("sops", ROOT / "k8s/infra/storage/basic-auth.sops.yaml"),
]


@pytest.fixture
def catalog(monkeypatch: pytest.MonkeyPatch) -> Catalog:
    catalog = Catalog(Repo(ROOT))
    monkeypatch.setattr(Catalog, "refs", lambda self: REFS)
    return catalog


def test_rows_name_the_containing_file(catalog: Catalog) -> None:
    rows = list(catalog.rows())
    assert rows[0].split() == ["vault_postgres_pass", "ansible/group_vars/all/vault.yml"]
    assert rows[2].split() == ["basic-auth", "k8s/infra/storage/basic-auth.sops.yaml"]


def test_rows_align_the_key_column(catalog: Catalog) -> None:
    starts = {row.index(row.split()[1]) for row in catalog.rows()}
    assert len(starts) == 1  # every path begins at the same column


def test_rows_map_back_to_their_ref(catalog: Catalog) -> None:
    assert list(catalog.rows().values()) == REFS


def test_sops_refs_are_whole_files_named_by_stem(catalog: Catalog) -> None:
    assert REFS[2].key is None
    assert REFS[2].name == "basic-auth"
    assert REFS[0].name == "vault_postgres_pass"
