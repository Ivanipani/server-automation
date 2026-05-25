#!/usr/bin/env python3
"""Reconcile ufw rules for one firewall-basic invocation scope.

Each role invocation passes its scope label and the desired rule set this
run wants enforced. The reconciler identifies role-owned rules in the
live ufw state via two signals:

  * the current tagged comment ``firewall-basic[<scope>]:`` — claimed by
    THIS scope; or
  * one of the legacy comment patterns this role used before
    reconciliation existed (``Allow SSH``, ``Allow inbound N/proto``,
    ``Allow outbound N/proto``, ``Deny outbound N/proto``) — claimed by
    whichever scope runs first on a host with pre-rewrite ufw state. A
    one-time migration: once the role has run, all role-managed rules
    carry the new tag and the legacy regex matches nothing further.

Any role-owned rule whose canonical key ``(rule, direction, port, proto)``
is NOT in the desired set is deleted. Rules tagged with a different
scope's prefix are left untouched, so plays managing overlapping hosts
don't fight.

Usage::

    ufw_reconcile.py <scope> <desired-json-string>

Output (stdout): ``{"deleted": [<rule>, ...]}`` for the calling task's
``changed_when``.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys

# `ufw show added` emits one user rule per line as a re-invocable command:
#   ufw allow 22/tcp comment 'Allow SSH'
#   ufw deny out 22/tcp comment 'Deny outbound 22/tcp'
# Inbound is implicit (no ``in`` keyword); outbound is explicit ``out``.
RULE_LINE = re.compile(
    r"^ufw\s+(?P<rule>allow|deny)(?:\s+(?P<direction>in|out))?\s+"
    r"(?P<port>\d+)/(?P<proto>tcp|udp)\s+comment\s+'(?P<comment>.+)'\s*$"
)

LEGACY_COMMENT = re.compile(
    r"^(Allow SSH"
    r"|Allow (?:inbound|outbound) \d+/(?:tcp|udp)"
    r"|Deny outbound \d+/(?:tcp|udp))$"
)


def canonical(rule: dict) -> tuple:
    return (rule["rule"], rule["direction"], int(rule["port"]), rule["proto"])


def ufw_delete(rule: dict) -> None:
    args = ["ufw", "delete", rule["rule"]]
    if rule["direction"] == "out":
        args.append("out")
    args.append(f"{rule['port']}/{rule['proto']}")
    # No ``check=True``: ufw returns rc=1 with "Could not delete non-existent
    # rule" if the rule was already removed out-of-band. That's the desired
    # end-state, not an error.
    subprocess.run(args, capture_output=True, text=True)


def list_added_rules() -> list[dict]:
    result = subprocess.run(
        ["ufw", "show", "added"], check=True, capture_output=True, text=True
    )
    rules: list[dict] = []
    for line in result.stdout.splitlines():
        match = RULE_LINE.match(line)
        if not match:
            continue
        parsed = match.groupdict()
        parsed["direction"] = parsed["direction"] or "in"
        rules.append(parsed)
    return rules


def main() -> None:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: ufw_reconcile.py <scope> <desired-json>\n")
        sys.exit(2)

    scope = sys.argv[1]
    desired = json.loads(sys.argv[2])
    own_tag = f"firewall-basic[{scope}]:"
    desired_keys = {canonical(r) for r in desired}

    deleted: list[dict] = []
    for rule in list_added_rules():
        comment = rule["comment"]
        owned = comment.startswith(own_tag) or bool(LEGACY_COMMENT.match(comment))
        if not owned:
            continue
        if canonical(rule) in desired_keys:
            continue
        ufw_delete(rule)
        deleted.append(rule)

    json.dump({"deleted": deleted}, sys.stdout)


if __name__ == "__main__":
    main()
