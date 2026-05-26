#!/usr/bin/env python3
"""Identify role-managed ufw rules that should be deleted.

Reads ``ufw show added``, extracts the comment from each line, and
identifies role-owned rules by:

  * the current tagged format ``firewall-basic[<scope>]: <rule> <dir>
    <port>/<proto>[ from <ip>][ to <ip>]`` (only when ``<scope>`` matches
    this invocation), or
  * one of the legacy comment patterns this role used before
    reconciliation existed (``Allow SSH``, ``Allow inbound N/proto``,
    ``Allow outbound N/proto``, ``Deny outbound N/proto``). Claimed by
    whichever scope runs first — a one-time migration.

For each role-owned rule whose canonical
``(rule, direction, port, proto, from_ip, to_ip)`` tuple is NOT in the
desired set, emit it to the orphans list.

Comments are the source of truth for rule spec (the role writes them on
add, so they're a deterministic encoding of what we asked ufw to
enforce). The reconciler never tries to parse ufw's free-form rule
display — that varies across ufw versions and scoping forms.

Usage::

    ufw_reconcile.py <scope> <desired-json-string>

Output (stdout): ``{"orphans": [<rule>, ...]}``. The calling ansible
task feeds each orphan back through ``community.general.ufw`` with
``delete=true`` so the module handles ufw's quirky delete-syntax for
scoped rules.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys

TAGGED_COMMENT = re.compile(
    r"^firewall-basic\[(?P<scope>[^\]]+)\]:\s+"
    r"(?P<rule>allow|deny)\s+(?P<direction>in|out)\s+"
    r"(?P<port>\d+)/(?P<proto>tcp|udp)"
    r"(?:\s+from\s+(?P<from_ip>\S+))?"
    r"(?:\s+to\s+(?P<to_ip>\S+))?\s*$"
)

LEGACY_SSH = re.compile(r"^Allow SSH$")
LEGACY_INBOUND = re.compile(r"^Allow inbound (?P<port>\d+)/(?P<proto>tcp|udp)$")
LEGACY_OUT_ALLOW = re.compile(r"^Allow outbound (?P<port>\d+)/(?P<proto>tcp|udp)$")
LEGACY_OUT_DENY = re.compile(r"^Deny outbound (?P<port>\d+)/(?P<proto>tcp|udp)$")

COMMENT_EXTRACT = re.compile(r"comment\s+'(?P<comment>.+)'\s*$")


def parse_comment(comment: str, scope: str) -> dict | None:
    """Return canonical rule dict if comment is owned by THIS scope or matches
    a legacy pattern (claimed regardless of scope). Otherwise None.
    """
    match = TAGGED_COMMENT.match(comment)
    if match and match.group("scope") == scope:
        rule = {
            "rule": match.group("rule"),
            "direction": match.group("direction"),
            "port": match.group("port"),
            "proto": match.group("proto"),
        }
        if match.group("from_ip"):
            rule["from_ip"] = match.group("from_ip")
        if match.group("to_ip"):
            rule["to_ip"] = match.group("to_ip")
        return rule

    if LEGACY_SSH.match(comment):
        return {"rule": "allow", "direction": "in", "port": "22", "proto": "tcp"}
    match = LEGACY_INBOUND.match(comment)
    if match:
        return {
            "rule": "allow",
            "direction": "in",
            "port": match.group("port"),
            "proto": match.group("proto"),
        }
    match = LEGACY_OUT_ALLOW.match(comment)
    if match:
        return {
            "rule": "allow",
            "direction": "out",
            "port": match.group("port"),
            "proto": match.group("proto"),
        }
    match = LEGACY_OUT_DENY.match(comment)
    if match:
        return {
            "rule": "deny",
            "direction": "out",
            "port": match.group("port"),
            "proto": match.group("proto"),
        }
    return None


def canonical(rule: dict) -> tuple:
    return (
        rule["rule"],
        rule["direction"],
        str(rule["port"]),
        rule["proto"],
        rule.get("from_ip") or "",
        rule.get("to_ip") or "",
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: ufw_reconcile.py <scope> <desired-json>\n")
        sys.exit(2)

    scope = sys.argv[1]
    desired = json.loads(sys.argv[2])
    desired_keys = {canonical(r) for r in desired}

    result = subprocess.run(
        ["ufw", "show", "added"], check=True, capture_output=True, text=True
    )

    orphans: list[dict] = []
    for line in result.stdout.splitlines():
        match = COMMENT_EXTRACT.search(line)
        if not match:
            continue
        rule = parse_comment(match.group("comment"), scope)
        if rule is None:
            continue
        if canonical(rule) in desired_keys:
            continue
        orphans.append(rule)

    json.dump({"orphans": orphans}, sys.stdout)


if __name__ == "__main__":
    main()
