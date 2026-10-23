"""Private, request-reloaded beta policy and local administrative operations."""
import hashlib
import ipaddress
import json
import math
import re
import secrets
from datetime import timedelta
from urllib.parse import urlsplit

from django.db import transaction
from django.utils import timezone

from backend import service
from backend.accounts.models import Account, BetaAccess, BetaInvite


class BetaConfigError(Exception):
    """Never expose config contents or private paths in the HTTP boundary."""


def _host(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 253 or not value.isascii():
        return False
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label)
                   for label in value.removesuffix('.').split('.'))


def _account_url(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 2048 or not value.isascii():
        return False
    if any(ord(char) <= 32 or ord(char) == 127 for char in value) or '\\' in value:
        return False
    try:
        url = urlsplit(value)
        return (url.scheme == 'https' and _host(url.hostname) and url.username is None
                and url.password is None and not url.query and not url.fragment
                and (url.port is None or 1 <= url.port <= 65535))
    except ValueError:
        return False


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise BetaConfigError()
        result[key] = value
    return result


def load_policy():
    """Missing file is local development; every malformed existing file fails closed."""
    try:
        path = service.DATA / 'beta.json'
        if path.stat().st_size > 65536:
            raise BetaConfigError()
        config = json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=_unique_object)
    except FileNotFoundError:
        return {'enabled': False}
    except (OSError, ValueError, RecursionError) as error:
        raise BetaConfigError() from error
    if (not isinstance(config, dict) or type(config.get('schema')) is not int
            or config['schema'] != 1 or type(config.get('enabled')) is not bool):
        raise BetaConfigError()
    policy = {'enabled': config['enabled']}
    if config['enabled'] or 'release_id' in config:
        release = config.get('release_id')
        if not isinstance(release, str) or not re.fullmatch(r'[A-Za-z0-9._-]{1,80}', release):
            raise BetaConfigError()
        policy['release_id'] = release
    validators = {
        'account_url': _account_url,
        'world_host': _host,
        'world_port': lambda v: type(v) is int and 1 <= v <= 65535,
        'world_id': lambda v: isinstance(v, str) and re.fullmatch(r'[A-Za-z0-9_.:-]{1,80}', v),
        'client_sha256': lambda v: isinstance(v, str) and re.fullmatch(r'[0-9a-f]{64}', v),
        'client_bytes': lambda v: type(v) is int and 1 <= v <= 4294967296,
    }
    for field, validate in validators.items():
        if field in config:
            if not validate(config[field]):
                raise BetaConfigError()
            policy[field] = config[field]
    return policy


def invite_digest(code):
    return hashlib.sha256(code.encode('utf-8')).hexdigest()


def create_invite(hours=72):
    if not isinstance(hours, (int, float)) or isinstance(hours, bool) or not math.isfinite(hours) or not 0 < hours <= 8760:
        raise ValueError('Invite lifetime must be greater than zero and at most 8760 hours.')
    code = secrets.token_urlsafe(32)
    BetaInvite.objects.create(code_hash=invite_digest(code), expires_at=timezone.now()+timedelta(hours=hours))
    return code


def set_access(username, granted):
    if not isinstance(username, str) or not re.fullmatch(r'[A-Za-z0-9_]{3,20}', username):
        raise ValueError('Use an existing account username.')
    with transaction.atomic():
        account = Account.objects.select_for_update().filter(username_key=username.lower()).first()
        if account is None:
            raise ValueError('Account does not exist.')
        BetaAccess.objects.update_or_create(account=account, defaults={'granted': bool(granted)})
    return {'username': account.username, 'granted': bool(granted)}


def status():
    """Deliberate allowlist: no password hashes, invite hashes, or private config."""
    now = timezone.now()
    return {
        'accounts': list(BetaAccess.objects.order_by('account__username_key').values('account__username', 'granted')),
        'invites': {
            'available': BetaInvite.objects.filter(consumed_at__isnull=True, expires_at__gt=now).count(),
            'expired': BetaInvite.objects.filter(consumed_at__isnull=True, expires_at__lte=now).count(),
            'consumed': BetaInvite.objects.filter(consumed_at__isnull=False).count(),
        },
    }
