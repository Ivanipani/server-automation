"""SOPS-encrypted YAML, handled a **whole file at a time** — read the manifest,
write the manifest. There is deliberately no per-key API.

Two sharp edges this module absorbs:

* `sops` looks for `.sops.yaml` relative to the **current working directory**,
  not to the file it is encrypting, so every invocation passes an explicit
  `--config` resolved by walking up from the target.
* Encrypting means the plaintext has to exist on disk for a moment. It is
  written to a `0600` sibling temp file (still named `*.sops.yaml`, so the
  config's `path_regex` matches), encrypted there, verified, and only then
  renamed over the target. Plaintext never appears at the real path.
"""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

import yaml

from elysium.errors import ElysiumError
from elysium.process import run, run_interactive

SOPS_METADATA_KEY = "sops"
SOPS_CONFIG_NAME = ".sops.yaml"
_SOPS_SUFFIXES = (".sops.yaml", ".sops.yml")


def _temp_suffix(path: Path) -> str:
    """Keep the temp file matching the same creation rule as the target."""
    for suffix in _SOPS_SUFFIXES:
        if path.name.endswith(suffix):
            return suffix
    return path.suffix


def _parse(text: str, *, source: str) -> object:
    try:
        return yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ElysiumError(f"{source} is not valid YAML: {exc}") from exc


@dataclass(frozen=True)
class SopsFile:
    """An encrypted manifest on disk."""

    path: Path

    def raw(self) -> dict:
        loaded = yaml.safe_load(self.path.read_text())
        if not isinstance(loaded, dict):
            raise ElysiumError(f"{self.path} is not a YAML mapping")
        return loaded

    def metadata(self) -> dict:
        return self.raw().get(SOPS_METADATA_KEY) or {}

    def is_encrypted(self) -> bool:
        return self.path.is_file() and bool(self.metadata())


@dataclass(frozen=True)
class SopsStore:
    """Whole-file SOPS operations bound to one age identity."""

    age_key_file: Path | None
    binary: str = "sops"

    @classmethod
    def from_repo(cls, repo) -> SopsStore:
        return cls(age_key_file=repo.age_key_file)

    @property
    def env(self) -> dict[str, str]:
        return {"SOPS_AGE_KEY_FILE": str(self.age_key_file)} if self.age_key_file else {}

    def file(self, path: Path) -> SopsFile:
        return SopsFile(path)

    def config_for(self, path: Path) -> Path | None:
        """Nearest `.sops.yaml` at or above `path`."""
        start = path if path.is_dir() else path.parent
        for directory in (start.resolve(), *start.resolve().parents):
            candidate = directory / SOPS_CONFIG_NAME
            if candidate.is_file():
                return candidate
        return None

    def _argv(self, path: Path, *args: str) -> list[str]:
        config = self.config_for(path)
        prefix = ["--config", str(config)] if config else []
        return [self.binary, *prefix, *args]

    def decrypt(self, path: Path) -> str:
        """The whole manifest, decrypted. The `sops:` metadata block is dropped
        by sops itself, so this is exactly what `write` accepts back."""
        return run(self._argv(path, "decrypt", str(path)), env=self.env)

    def write(self, path: Path, text: str, *, verify: bool = True) -> bool:
        """Replace the whole manifest with `text` (plaintext YAML), encrypted.

        Returns True if the file already existed. Atomic: the target is only
        touched by the final rename.
        """
        _parse(text, source="input")
        existed = path.exists()
        mode = path.stat().st_mode & 0o777 if existed else 0o600

        handle, name = tempfile.mkstemp(
            dir=str(path.parent), prefix=f".{path.name}.", suffix=_temp_suffix(path)
        )
        tmp = Path(name)
        try:
            with os.fdopen(handle, "w") as stream:
                stream.write(text)
            run(self._argv(path, "encrypt", "--in-place", str(tmp)), env=self.env)
            if verify:
                self._verify(tmp, text)
            tmp.chmod(mode)
            tmp.replace(path)
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise
        return existed

    def _verify(self, encrypted: Path, expected: str) -> None:
        roundtrip = run(self._argv(encrypted, "decrypt", str(encrypted)), env=self.env)
        if _parse(roundtrip, source="re-decrypted output") != _parse(expected, source="input"):
            raise ElysiumError("verification failed: the encrypted file did not decrypt to the input")

    def edit(self, path: Path) -> None:
        run_interactive(self._argv(path, str(path)), env=self.env)

    def encrypt_in_place(self, path: Path) -> None:
        run(self._argv(path, "encrypt", "--in-place", str(path)), env=self.env)
