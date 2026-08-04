"""Vault files are found by content, so no path or filename is privileged."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from elysium.repo import Repo
from elysium.vault import VaultIndex, holds_vault_entries

VAULTED = textwrap.dedent(
    """\
    # secrets
    vault_postgres_pass: !vault |
              $ANSIBLE_VAULT;1.2;AES256;dev
              3737323536663262
    """
)


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


@pytest.fixture
def repo(tmp_path: Path) -> Repo:
    (tmp_path / ".git").mkdir()
    return Repo(tmp_path)


def test_detects_a_vault_entry(tmp_path: Path) -> None:
    assert holds_vault_entries(write(tmp_path / "anything.yml", VAULTED))


def test_ignores_plain_yaml_and_bare_mentions(tmp_path: Path) -> None:
    assert not holds_vault_entries(write(tmp_path / "plain.yml", "key: value\n"))
    # `!vault` in prose is not an entry.
    assert not holds_vault_entries(write(tmp_path / "prose.yml", "# use !vault for secrets\n"))


def test_ignores_unreadable_and_binary_files(tmp_path: Path) -> None:
    assert not holds_vault_entries(tmp_path / "missing.yml")
    (tmp_path / "blob.yml").write_bytes(b"\xff\xfe\x00binary")
    assert not holds_vault_entries(tmp_path / "blob.yml")


def test_finds_vault_files_anywhere_in_the_tree(repo: Repo) -> None:
    expected = [
        write(repo.root / "ansible/group_vars/all/vault.yml", VAULTED),
        write(repo.root / "ansible/group_vars/prod/vault.yml", VAULTED),
        write(repo.root / "apps/nested/deep/creds.yaml", VAULTED),
    ]
    write(repo.root / "ansible/group_vars/all/main.yml", "key: value\n")
    assert repo.ansible_vault_files == sorted(expected)


def test_skips_pruned_and_hidden_paths(repo: Repo) -> None:
    kept = write(repo.root / "vars.yml", VAULTED)
    write(repo.root / ".venv/lib/fixture.yml", VAULTED)
    write(repo.root / "node_modules/pkg/fixture.yml", VAULTED)
    write(repo.root / ".hidden.yml", VAULTED)
    assert repo.ansible_vault_files == [kept]


def test_no_vault_files_is_not_an_error(repo: Repo) -> None:
    write(repo.root / "plain.yml", "key: value\n")
    assert repo.ansible_vault_files == []


def test_index_maps_names_to_the_files_holding_them(repo: Repo) -> None:
    write(repo.root / "secrets/ansible-pass", "pw\n")
    shared = VAULTED.replace("vault_postgres_pass", "shared")
    all_vars = write(repo.root / "group_vars/all.yml", VAULTED + shared)
    prod = write(repo.root / "group_vars/prod.yml", shared)

    index = VaultIndex.from_repo(repo)
    assert index.entries() == [
        (index.store(all_vars), "vault_postgres_pass"),
        (index.store(all_vars), "shared"),
        (index.store(prod), "shared"),
    ]
    # A name is unique per file, not per repo.
    assert [s.path for s in index.stores_with("shared")] == [all_vars, prod]
    assert [s.path for s in index.stores_with("vault_postgres_pass")] == [all_vars]
    assert index.stores_with("nope") == []


def test_index_can_be_scoped_to_given_files(repo: Repo) -> None:
    write(repo.root / "secrets/ansible-pass", "pw\n")
    write(repo.root / "group_vars/all.yml", VAULTED)
    prod = write(repo.root / "group_vars/prod.yml", VAULTED)

    index = VaultIndex.from_repo(repo, [prod])
    assert [s.path for s in index.stores] == [prod]
