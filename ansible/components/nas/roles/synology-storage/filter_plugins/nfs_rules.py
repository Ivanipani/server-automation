# -*- coding: utf-8 -*-
#
# Filters that translate inventory-shaped NFS export rules into the
# JSON shape DSM's SYNO.Core.FileServ.NFS.SharePrivilege/save expects.
#
# Inventory shape (operator-friendly, NFS-standard terms):
#   { host: <cidr-or-hostname>,
#     privilege: rw | ro,
#     squash: no_root_squash | root_squash | all_squash,
#     security: sys | krb5 | krb5i | krb5p,
#     async: true | false }
#
# DSM shape (what SharePrivilege/save expects, re-captured live from
# DSM 7.3.2 on 2026-05-26 — the May 21 capture's 3-way `root_squash`
# enum was rejected with error 2301 by the current DSM patch):
#   { "client": <cidr-or-hostname>,
#     "privilege": "rw" | "ro",
#     "root_squash": "no_map" | "root_admin" | "root_guest"
#                  | "all_admin" | "all_guest",   # <scope>_<target>
#     "async": bool,
#     "insecure": bool,                           # "allow non-priv ports"
#     "crossmnt": bool,                           # "allow subfolder access"
#     "security_flavor": { sys: bool, kerberos: bool,
#                          kerberos_integrity: bool,
#                          kerberos_privacy: bool } }
#
# `insecure` and `crossmnt` default to false in our translation (matching
# DSM 7.3 UI's current defaults). Expose them in the inventory schema
# if/when someone needs them on.

from __future__ import absolute_import, division, print_function
__metaclass__ = type


# Inventory squash term  →  DSM root_squash enum value.
# Inventory uses NFS-standard terms. DSM's enum is <scope>_<target>:
#   scope = which clients to squash: root only, or all users
#   target = squash destination: admin, or guest
# For the homelab single-admin model the only activated DSM user is
# `pani` (an admin), so admin-target maps to pani. To squash to guest,
# enable the built-in DSM guest user and switch the mapping below.
_SQUASH_MAP = {
    'no_root_squash': 'no_map',      # do not squash anyone
    'root_squash':    'root_admin',  # squash root only → admin
    'all_squash':     'all_admin',   # squash everyone → admin
}


def dsm_nfs_rule(rule):
    """Translate one inventory NFS rule dict to DSM's SharePrivilege rule shape."""
    if not isinstance(rule, dict):
        raise TypeError('dsm_nfs_rule expects a dict, got %s' % type(rule).__name__)

    squash_term = rule.get('squash', 'no_root_squash')
    if squash_term not in _SQUASH_MAP:
        raise ValueError(
            'unknown squash term %r; expected one of %s'
            % (squash_term, sorted(_SQUASH_MAP.keys()))
        )

    security = rule.get('security', 'sys')

    return {
        'client':      rule['host'],
        'privilege':   rule.get('privilege', 'rw'),
        'root_squash': _SQUASH_MAP[squash_term],
        'async':       bool(rule.get('async', True)),
        'insecure':    bool(rule.get('insecure', False)),
        'crossmnt':    bool(rule.get('crossmnt', False)),
        'security_flavor': {
            'sys':                security == 'sys',
            'kerberos':           security == 'krb5',
            'kerberos_integrity': security == 'krb5i',
            'kerberos_privacy':   security == 'krb5p',
        },
    }


class FilterModule(object):
    def filters(self):
        return {
            'dsm_nfs_rule': dsm_nfs_rule,
        }
