"""Whole-file SOPS behaviour that does not need a real age key."""

from __future__ import annotations

from pathlib import Path

import pytest

from elysium.errors import ElysiumError
from elysium.sops import SopsFile, SopsStore, _temp_suffix

PLAINTEXT = "kind: Secret\n# keep me\nstringData:\n  token: hunter2\n"
ENCRYPTED = PLAINTEXT + "sops:\n  version: 3.13.0\n"


@pytest.fixture
def store() -> SopsStore:
    return SopsStore(age_key_file=Path("/keys/age.agekey"))


def test_config_is_the_nearest_sops_yaml_above_the_file(tmp_path: Path, store: SopsStore) -> None:
    (tmp_path / "k8s").mkdir()
    (tmp_path / "k8s" / ".sops.yaml").write_text("creation_rules: []\n")
    nested = tmp_path / "k8s" / "infra" / "app"
    nested.mkdir(parents=True)
    target = nested / "a.sops.yaml"
    target.write_text(ENCRYPTED)
    assert store.config_for(target) == tmp_path / "k8s" / ".sops.yaml"


def test_config_is_none_when_no_rules_exist(tmp_path: Path, store: SopsStore) -> None:
    target = tmp_path / "a.sops.yaml"
    target.write_text(ENCRYPTED)
    assert store.config_for(target) is None


def test_argv_passes_the_config_explicitly(tmp_path: Path, store: SopsStore) -> None:
    (tmp_path / ".sops.yaml").write_text("creation_rules: []\n")
    target = tmp_path / "a.sops.yaml"
    target.write_text(ENCRYPTED)
    assert store._argv(target, "decrypt")[:3] == ["sops", "--config", str(tmp_path / ".sops.yaml")]


def test_temp_file_keeps_the_sops_suffix_so_creation_rules_still_match() -> None:
    assert _temp_suffix(Path("basic-auth.sops.yaml")) == ".sops.yaml"
    assert _temp_suffix(Path("basic-auth.sops.yml")) == ".sops.yml"
    assert _temp_suffix(Path("plain.yaml")) == ".yaml"


def test_write_rejects_invalid_yaml_before_touching_the_target(tmp_path: Path, store: SopsStore) -> None:
    target = tmp_path / "a.sops.yaml"
    target.write_text(ENCRYPTED)
    with pytest.raises(ElysiumError, match="not valid YAML"):
        store.write(target, "key: [unclosed\n")
    assert target.read_text() == ENCRYPTED  # untouched
    assert list(tmp_path.glob(".*")) == []  # no temp file left behind


def test_write_leaves_no_plaintext_when_encryption_fails(
    tmp_path: Path, store: SopsStore, monkeypatch: pytest.MonkeyPatch
) -> None:
    target = tmp_path / "a.sops.yaml"
    target.write_text(ENCRYPTED)

    def boom(*args, **kwargs):
        raise ElysiumError("sops exploded")

    monkeypatch.setattr("elysium.sops.run", boom)
    with pytest.raises(ElysiumError, match="exploded"):
        store.write(target, PLAINTEXT)

    assert target.read_text() == ENCRYPTED
    assert list(tmp_path.iterdir()) == [target]  # the 0600 temp file is gone


def test_is_encrypted_reads_the_metadata_block(tmp_path: Path) -> None:
    encrypted = tmp_path / "a.sops.yaml"
    encrypted.write_text(ENCRYPTED)
    plain = tmp_path / "b.sops.yaml"
    plain.write_text(PLAINTEXT)
    assert SopsFile(encrypted).is_encrypted()
    assert not SopsFile(plain).is_encrypted()
    assert not SopsFile(tmp_path / "missing.sops.yaml").is_encrypted()
