"""The contract that matters: rewriting one entry must not disturb a single
byte of anything else in the file."""

from __future__ import annotations

import re
import textwrap

import pytest

from elysium.errors import ElysiumError, EntryNotFound
from elysium.vault import VaultDocument

SAMPLE = """\
---
# Central vault for all encrypted secrets
# Encrypt values with: ansible-vault encrypt_string '<value>' --name '<var_name>'

# Database passwords
vault_postgres_pass: !vault |
          $ANSIBLE_VAULT;1.2;AES256;dev
          3737323536663262
          3333393336336264

vault_router_root_pass: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          6239373831383263

# trailing comment
"""

NEW_CIPHERTEXT = "$ANSIBLE_VAULT;1.1;AES256\naaaa\nbbbb\ncccc"


@pytest.fixture
def document() -> VaultDocument:
    return VaultDocument(SAMPLE)


def test_parses_entries(document: VaultDocument) -> None:
    assert document.names() == ["vault_postgres_pass", "vault_router_root_pass"]


def test_entry_exposes_block_geometry(document: VaultDocument) -> None:
    entry = document.get("vault_postgres_pass")
    assert entry.body_indent == " " * 10
    assert entry.key_indent == ""
    assert entry.ciphertext == "$ANSIBLE_VAULT;1.2;AES256;dev\n3737323536663262\n3333393336336264"
    assert entry.vault_id == "dev"


def test_missing_entry_raises(document: VaultDocument) -> None:
    with pytest.raises(EntryNotFound):
        document.get("nope")


def test_replace_touches_only_the_target_block(document: VaultDocument) -> None:
    assert document.set("vault_postgres_pass", NEW_CIPHERTEXT) is True
    assert document.text == SAMPLE.replace(
        "          $ANSIBLE_VAULT;1.2;AES256;dev\n          3737323536663262\n          3333393336336264",
        "          $ANSIBLE_VAULT;1.1;AES256\n          aaaa\n          bbbb\n          cccc",
    )


def test_replace_preserves_comments_and_blank_lines(document: VaultDocument) -> None:
    document.set("vault_router_root_pass", NEW_CIPHERTEXT)
    lines = document.text.splitlines()
    assert lines[1] == "# Central vault for all encrypted secrets"
    assert lines[4] == "# Database passwords"
    assert lines[-1] == "# trailing comment"
    assert "" in lines  # blank separators survive
    assert document.names() == ["vault_postgres_pass", "vault_router_root_pass"]


def test_replace_is_idempotent_for_identical_ciphertext(document: VaultDocument) -> None:
    entry = document.get("vault_postgres_pass")
    document.set("vault_postgres_pass", entry.ciphertext)
    assert document.text == SAMPLE


def test_append_new_entry_matches_existing_indentation(document: VaultDocument) -> None:
    assert document.set("vault_new_thing", NEW_CIPHERTEXT) is False
    assert document.text.startswith(SAMPLE)
    assert document.text.endswith(
        "vault_new_thing: !vault |\n          $ANSIBLE_VAULT;1.1;AES256\n          aaaa\n          bbbb\n          cccc\n"
    )
    assert document.get("vault_new_thing").ciphertext == NEW_CIPHERTEXT


def test_append_to_file_without_trailing_newline() -> None:
    document = VaultDocument("vault_a: !vault |\n          $ANSIBLE_VAULT;1.1;AES256\n          dead")
    document.set("vault_b", NEW_CIPHERTEXT)
    assert document.names() == ["vault_a", "vault_b"]
    assert document.text.endswith("\n")


def test_indented_nested_entries_keep_their_indentation() -> None:
    nested = textwrap.dedent(
        """\
        parent:
          child_secret: !vault |
            $ANSIBLE_VAULT;1.1;AES256
            beef
        sibling: plain
        """
    )
    document = VaultDocument(nested)
    entry = document.get("child_secret")
    assert entry.key_indent == "  "
    assert entry.body_indent == "    "
    document.set("child_secret", "$ANSIBLE_VAULT;1.1;AES256\nf00d")
    assert document.text == nested.replace("beef", "f00d")
    assert document.names() == ["child_secret"]
    assert document.plain_keys() == ["parent", "sibling"]


def test_refuses_to_clobber_a_plaintext_key() -> None:
    document = VaultDocument("plain_key: hello\n")
    assert document.plain_keys() == ["plain_key"]
    with pytest.raises(ElysiumError, match="plaintext key"):
        document.set("plain_key", NEW_CIPHERTEXT)


def test_refuses_empty_ciphertext(document: VaultDocument) -> None:
    with pytest.raises(ElysiumError, match="empty"):
        document.set("vault_postgres_pass", "   \n  \n")


def test_crlf_line_endings_survive() -> None:
    document = VaultDocument(SAMPLE.replace("\n", "\r\n"))
    document.set("vault_postgres_pass", NEW_CIPHERTEXT)
    assert document.text == SAMPLE.replace(
        "          $ANSIBLE_VAULT;1.2;AES256;dev\n          3737323536663262\n          3333393336336264",
        "          $ANSIBLE_VAULT;1.1;AES256\n          aaaa\n          bbbb\n          cccc",
    ).replace("\n", "\r\n")
    assert not re.findall(r"(?<!\r)\n", document.text)


def test_save_preserves_permissions(tmp_path) -> None:
    path = tmp_path / "vault.yml"
    path.write_text(SAMPLE)
    path.chmod(0o600)
    document = VaultDocument.load(path)
    document.set("vault_postgres_pass", NEW_CIPHERTEXT)
    document.save()
    assert path.stat().st_mode & 0o777 == 0o600
    assert VaultDocument.load(path).get("vault_postgres_pass").ciphertext == NEW_CIPHERTEXT
