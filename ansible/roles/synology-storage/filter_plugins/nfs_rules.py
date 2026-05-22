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
# DSM shape (what SharePrivilege/save expects, observed live from DSM
# 7.3.2 UI on 2026-05-21):
#   { "client": <cidr-or-hostname>,
#     "privilege": "rw" | "ro",
#     "root_squash": "root" | "admin" | "all",   # 3-way enum, NOT a bool
#     "async": bool,
#     "insecure": bool,                          # "allow non-priv ports"
#     "crossmnt": bool,                          # "allow subfolder access"
#     "security_flavor": { sys: bool, kerberos: bool,
#                          kerberos_integrity: bool,
#                          kerberos_privacy: bool } }
#
# `insecure` and `crossmnt` default to true in our translation (matching
# the DSM UI defaults). Expose them in the inventory schema if/when
# someone needs them off.

from __future__ import absolute_import, division, print_function
__metaclass__ = type


# Inventory squash term  →  DSM root_squash enum value
# The enum value indicates "what to keep things AS":
#   "root"  = keep root as root (= no_root_squash in NFS-speak)
#   "admin" = map root to admin (= root_squash in NFS-speak)
#   "all"   = squash all users (= all_squash in NFS-speak)
_SQUASH_MAP = {
    'no_root_squash': 'root',
    'root_squash':    'admin',
    'all_squash':     'all',
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
        'insecure':    bool(rule.get('insecure', True)),
        'crossmnt':    bool(rule.get('crossmnt', True)),
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
