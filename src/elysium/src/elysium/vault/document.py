"""Surgical editing of an ansible-vault `group_vars` file.

The file is treated as **lines of text, not YAML**: an update rewrites only the
ciphertext lines of the targeted entry, so comments, blank lines, key order and
every byte of indentation elsewhere survive untouched. A YAML round-trip would
reflow the file; that is the whole reason this module exists.

A vaulted entry looks like:

    vault_postgres_pass: !vault |
              $ANSIBLE_VAULT;1.2;AES256;dev
              3737323536663262...
"""

from __future__ import annotations

import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path

from elysium.errors import ElysiumError, EntryNotFound

_KEY_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?P<name>[A-Za-z0-9_.\-]+)[ \t]*:(?P<rest>.*)$"
)
_VAULT_TAG = "!vault"
_VAULT_TAG_RE = re.compile(r"^[ \t]*!vault[ \t]*\|[-+]?[0-9]*[ \t]*$")

DEFAULT_BODY_INDENT = " " * 10  # what `ansible-vault encrypt_string` emits


def holds_vault_entries(path: Path) -> bool:
    """Whether `path` carries at least one `name: !vault |` entry.

    Content, not convention — this is how vault files are discovered, so no
    particular filename or directory is privileged.
    """
    try:
        text = path.read_text()
    except (OSError, UnicodeDecodeError):
        return False
    return _VAULT_TAG in text and bool(VaultDocument(text, path=path).entries())


def _indent_of(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


def _width(indent: str) -> int:
    return len(indent.expandtabs(8))


@dataclass(frozen=True)
class VaultEntry:
    """One `name: !vault |` block and the exact slice of lines it occupies."""

    name: str
    key_index: int
    body_start: int
    body_end: int
    key_indent: str
    body_indent: str
    ciphertext: str

    @property
    def header(self) -> str:
        """e.g. `$ANSIBLE_VAULT;1.2;AES256;dev` — the format/version/vault-id line."""
        return self.ciphertext.splitlines()[0] if self.ciphertext else ""

    @property
    def vault_id(self) -> str | None:
        parts = self.header.split(";")
        return parts[3] if len(parts) > 3 else None


class VaultDocument:
    """Line-oriented view of a vault file. Mutations preserve surrounding bytes."""

    def __init__(self, text: str, *, path: Path | None = None) -> None:
        self.path = path
        self.newline = "\r\n" if "\r\n" in text else "\n"
        self._ends_with_newline: bool = text.endswith(("\n", "\r"))
        self._lines = text.splitlines()

    @classmethod
    def load(cls, path: Path) -> VaultDocument:
        return cls(path.read_text(), path=path)

    @property
    def text(self) -> str:
        body = self.newline.join(self._lines)
        return body + self.newline if self._ends_with_newline and body else body

    # --- parsing -----------------------------------------------------------

    def entries(self) -> list[VaultEntry]:
        entries: list[VaultEntry] = []
        index = 0
        while index < len(self._lines):
            entry = self._parse_entry_at(index)
            if entry is None:
                index += 1
                continue
            entries.append(entry)
            index = max(entry.body_end, entry.key_index + 1)
        return entries

    def _parse_entry_at(self, index: int) -> VaultEntry | None:
        match = _KEY_RE.match(self._lines[index])
        if match is None or not _VAULT_TAG_RE.match(match.group("rest")):
            return None

        key_indent = match.group("indent")
        cursor = index + 1
        while cursor < len(self._lines):
            line = self._lines[cursor]
            if line.strip() and _width(_indent_of(line)) <= _width(key_indent):
                break
            cursor += 1
        # Trailing blank lines separate entries; they are not part of the block.
        body_end = cursor
        while body_end > index + 1 and not self._lines[body_end - 1].strip():
            body_end -= 1

        body = self._lines[index + 1 : body_end]
        non_blank = [line for line in body if line.strip()]
        body_indent = (
            _indent_of(non_blank[0]) if non_blank else key_indent + DEFAULT_BODY_INDENT
        )
        ciphertext = "\n".join(line.strip() for line in non_blank)

        return VaultEntry(
            name=match.group("name"),
            key_index=index,
            body_start=index + 1,
            body_end=body_end,
            key_indent=key_indent,
            body_indent=body_indent,
            ciphertext=ciphertext,
        )

    def names(self) -> list[str]:
        return [entry.name for entry in self.entries()]

    def find(self, name: str) -> VaultEntry | None:
        return next((entry for entry in self.entries() if entry.name == name), None)

    def get(self, name: str) -> VaultEntry:
        entry = self.find(name)
        if entry is None:
            where = f" in {self.path}" if self.path else ""
            raise EntryNotFound(f"no vaulted variable `{name}`{where}")
        return entry

    def plain_keys(self) -> list[str]:
        """Top-level-ish keys that are *not* vaulted — writing over one is refused."""
        covered = {
            i
            for entry in self.entries()
            for i in range(entry.key_index, entry.body_end)
        }
        keys: list[str] = []
        for index, line in enumerate(self._lines):
            if index in covered or line.lstrip().startswith("#"):
                continue
            match = _KEY_RE.match(line)
            if match:
                keys.append(match.group("name"))
        return keys

    # --- mutation ----------------------------------------------------------

    def set(self, name: str, ciphertext: str) -> bool:
        """Write `ciphertext` under `name`. Returns True if an entry was replaced,
        False if a new one was appended."""
        lines = [
            line.strip() for line in ciphertext.strip().splitlines() if line.strip()
        ]
        if not lines:
            raise ElysiumError("refusing to write an empty vault block")

        entry = self.find(name)
        if entry is not None:
            body = [entry.body_indent + line for line in lines]
            self._lines[entry.body_start : entry.body_end] = body
            return True

        if name in self.plain_keys():
            raise ElysiumError(
                f"`{name}` already exists as a plaintext key — refusing to clobber it"
            )
        self._append(name, lines)
        return False

    def _append(self, name: str, ciphertext_lines: list[str]) -> None:
        existing = self.entries()
        key_indent = existing[-1].key_indent if existing else ""
        body_indent = existing[-1].body_indent if existing else DEFAULT_BODY_INDENT
        if self._lines and self._lines[-1].strip():
            self._lines.append("")
        self._lines.append(f"{key_indent}{name}: !vault |")
        self._lines.extend(body_indent + line for line in ciphertext_lines)
        self._ends_with_newline = True

    # --- persistence -------------------------------------------------------

    def save(self, path: Path | None = None) -> Path:
        """Atomically replace the file, keeping its permission bits."""
        target = path or self.path
        if target is None:
            raise ElysiumError("VaultDocument has no path to save to")
        mode = target.stat().st_mode & 0o777 if target.exists() else 0o600
        handle, tmp_name = tempfile.mkstemp(
            dir=str(target.parent), prefix=f".{target.name}."
        )
        tmp = Path(tmp_name)
        try:
            with os.fdopen(handle, "w") as stream:
                stream.write(self.text)
            tmp.chmod(mode)
            tmp.replace(target)
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise
        self.path = target
        return target
