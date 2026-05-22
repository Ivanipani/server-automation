# -*- coding: utf-8 -*-
#
# Thin facade over ansible.builtin.uri for the Synology DSM JSON API.
#
# Forked from agaffney/ansible-synology-dsm (MIT, 2019). Differences from
# upstream:
#   - HTTPS-first; `validate_certs` is threaded through to `uri` (upstream
#     ignored it entirely).
#   - `timeout` threaded through.
#   - GET requests no longer pass api_params in the query string for
#     login calls — the caller must use POST for anything carrying a
#     password. (We can't *force* POST here without breaking the simple
#     GET-for-query use cases like SYNO.API.Info, so the rule is
#     enforced at the task level — see tasks/login.yml.)
#   - DSM `error.code` is surfaced on failure instead of a bare "failed".
#   - Removed the upstream `_remove_tmp_path(self._connection._shell.tmpdir)`
#     call — that touched private Ansible attrs and is unnecessary because
#     `uri` runs locally and transfers no files.
#
# This file lives under roles/synology-dsm/action_plugins/ so Ansible
# auto-loads it when the role is in use. No ansible.cfg change needed.

from __future__ import absolute_import, division, print_function
__metaclass__ = type

from ansible.plugins.action import ActionBase

try:
    # py3
    from urllib.parse import urlencode
except ImportError:  # pragma: no cover
    # py2 — kept only because Ansible still tolerates 2.7 control nodes
    # in some distros; remove when min ansible is 2.16+ everywhere.
    from urllib import urlencode


# DSM error.code → human reason. Not exhaustive; common codes only.
# Source: Synology File Station API Guide + observed during testing.
_DSM_AUTH_ERRORS = {
    100: "unknown error",
    101: "no parameter of API, method or version",
    102: "the requested API does not exist",
    103: "the requested method does not exist",
    104: "the requested version does not support the functionality",
    105: "the logged-in session does not have permission",
    106: "session timeout",
    107: "session interrupted by duplicate login",
    400: "no such account or incorrect password",
    401: "disabled account",
    402: "denied permission",
    403: "2-factor authentication code required",
    404: "failed to authenticate 2-factor authentication code",
    405: "App portal incorrect",
    406: "OTP code enforced",
    407: "max tries (login attempts) reached — temporarily locked out",
    408: "password expired and cannot be changed",
    409: "password expired",
    410: "password must be changed (administrator policy)",
    411: "account locked (by administrator)",
}


class ActionModule(ActionBase):

    TRANSFERS_FILES = False

    PARAM_DEFAULTS = dict(
        base_url='https://localhost:5001',
        validate_certs=True,
        timeout=30,
        request_method='GET',
        login_cookie=None,
        # DSM's CSRF protection for write-sensitive APIs (Storage Manager,
        # Shared Folder management). Returned by login when the caller
        # passes `enable_syno_token: yes`; the cookie alone is sufficient
        # for reads and for the simpler File-Service writes (Terminal,
        # NFS/SMB toggles, User Home) but NOT for SYNO.Core.Share writes
        # or share-permission writes — those return code 403 without it.
        # When present we send it as the X-SYNO-TOKEN header; the cookie
        # still carries the session identity.
        synotoken=None,
        cgi_path='/webapi/',
        cgi_name='entry.cgi',
        api_name=None,
        api_version='1',
        api_method=None,
        api_params=None,
        request_json=None,
    )

    def run(self, tmp=None, task_vars=None):
        self._supports_async = True

        if task_vars is None:
            task_vars = dict()

        result = super(ActionModule, self).run(tmp, task_vars)
        del tmp  # tmp no longer has any effect

        # Merge defaults with task args; drop Nones so `in` checks below
        # work as "was this explicitly set".
        task_args = self.PARAM_DEFAULTS.copy()
        task_args.update(self._task.args)
        for arg in list(task_args.keys()):
            if task_args[arg] is None:
                del task_args[arg]

        # ---- Build the uri-module params -----------------------------------
        uri_params = dict(
            url="%s/%s/%s" % (
                task_args['base_url'],
                task_args['cgi_path'].strip('/'),
                task_args['cgi_name'],
            ),
            method=task_args['request_method'],
            validate_certs=bool(task_args.get('validate_certs', True)),
            timeout=int(task_args.get('timeout', 30)),
            # uri's default is text; we want the parsed JSON in result.json
            # so success-detection below works the same across DSM versions.
            return_content=True,
            status_code=[200],
        )

        if 'login_cookie' in task_args:
            uri_params['headers'] = dict(Cookie=task_args['login_cookie'])

        # SynoToken — DSM's CSRF protection. We send it as BOTH a header
        # (X-SYNO-TOKEN) and a URL query param (SynoToken=...) because
        # different code paths inside DSM read from different places.
        # The DSM UI itself sends it via the URL form on write calls; we
        # mirror that exactly for write-sensitive endpoints (Share,
        # Share.Permission, some Storage Manager methods).
        if 'synotoken' in task_args:
            uri_params.setdefault('headers', {})['X-SYNO-TOKEN'] = task_args['synotoken']

        if task_args['request_method'] == 'POST':
            if 'request_json' in task_args:
                uri_params['body'] = task_args['request_json']
                uri_params['body_format'] = 'json'
            else:
                tmp_body = dict(
                    api=task_args['api_name'],
                    version=task_args['api_version'],
                    method=task_args['api_method'],
                )
                if 'api_params' in task_args:
                    tmp_body.update(task_args['api_params'])
                uri_params['body'] = tmp_body
                uri_params['body_format'] = 'form-urlencoded'
        elif task_args['request_method'] == 'GET':
            uri_params['url'] += '?api=%s&version=%s&method=%s' % (
                task_args['api_name'],
                task_args['api_version'],
                task_args['api_method'],
            )
            if 'api_params' in task_args:
                uri_params['url'] += '&%s' % urlencode(task_args['api_params'])

        # DSM UI sends SynoToken in the URL on write calls. We append
        # AFTER the request-method dispatch so the right separator is
        # chosen for both POST (no query yet) and GET (query already
        # present).
        if 'synotoken' in task_args:
            sep = '&' if '?' in uri_params['url'] else '?'
            uri_params['url'] += '%sSynoToken=%s' % (sep, task_args['synotoken'])

        result.update(self._execute_module(
            'ansible.builtin.uri',
            module_args=uri_params,
            task_vars=task_vars,
            wrap_async=self._task.async_val,
        ))

        # ---- Surface DSM-level failures ------------------------------------
        # uri returns HTTP success even when DSM packed an error into the
        # JSON body. The body always carries `success: bool`; on false it
        # carries `error.code` (and sometimes `error.errors`).
        if not result.get('failed', False):
            body = result.get('json') or {}
            if body.get('success', None) is False:
                code = body.get('error', {}).get('code')
                reason = _DSM_AUTH_ERRORS.get(code, 'unrecognised DSM error code')
                result['failed'] = True
                result['msg'] = "DSM API call failed: code=%s (%s)" % (code, reason)
                result['dsm_error'] = body.get('error')

        return result
