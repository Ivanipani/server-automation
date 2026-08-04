"""ansible-vault crypto, shelled out to the `ansible-vault` binary.

Plaintext crosses the process boundary on stdin only.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from elysium.errors import ElysiumError
from elysium.process import run
from elysium.vault.document import DEFAULT_BODY_INDENT

VAULT_HEADER_PREFIX = "$ANSIBLE_VAULT"


@dataclass(frozen=True)
class VaultCrypto:
    password_file: Path
    binary: str = "ansible-vault"

    def _argv(self, action: str, *, vault_id: str | None = None) -> list[str]:
        # `--vault-id <label>@<file>` is what stamps the label into the header;
        # `--encrypt-vault-id` alone rejects any label it has no password for.
        auth = (
            ["--vault-id", f"{vault_id}@{self.password_file}"]
            if vault_id
            else ["--vault-password-file", str(self.password_file)]
        )
        return [self.binary, action, *auth, "--output", "-"]

    def encrypt(self, plaintext: str, *, vault_id: str | None = None) -> str:
        """Encrypt to a bare `$ANSIBLE_VAULT;...` blob (no YAML, no indentation)."""
        return run(self._argv("encrypt", vault_id=vault_id), stdin=plaintext).strip()

    def decrypt(self, ciphertext: str) -> str:
        """Decrypt a blob. Indentation is stripped first, so a block lifted
        straight out of a `!vault |` entry works as-is."""
        blob = "\n".join(
            line.strip() for line in ciphertext.strip().splitlines() if line.strip()
        )
        if not blob.startswith(VAULT_HEADER_PREFIX):
            raise ElysiumError(
                f"not an ansible-vault blob (expected a {VAULT_HEADER_PREFIX} header)"
            )
        return run(self._argv("decrypt"), stdin=blob + "\n")


def yaml_block(
    name: str,
    ciphertext: str,
    *,
    key_indent: str = "",
    body_indent: str = DEFAULT_BODY_INDENT,
) -> str:
    """Render a blob as a pasteable `name: !vault |` YAML block."""
    lines = [line.strip() for line in ciphertext.strip().splitlines() if line.strip()]
    body = "\n".join(f"{key_indent}{body_indent}{line}" for line in lines)
    return f"{key_indent}{name}: !vault |\n{body}"
