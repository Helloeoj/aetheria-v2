"""Small JSON boundary. Secrets and submitted state are deliberately never logged."""
import hashlib
import hmac
import ipaddress
import json
import math
import os
import re
import secrets
import threading
import time
import unicodedata
import uuid
from datetime import timedelta

from django.contrib.auth.hashers import check_password, make_password
from django.core.exceptions import RequestDataTooBig
from django.db import IntegrityError, OperationalError, transaction
from django.http import JsonResponse
from django.utils import timezone

from .models import Account, Admission, BetaAccess, BetaInvite, Character, Journal, RateLimit, Session
from backend.beta import BetaConfigError, invite_digest, load_policy

HASH_SLOTS = threading.BoundedSemaphore(2)
DUMMY_HASH = make_password(secrets.token_urlsafe(32))
LEASE_SECONDS = 30
TICKET_SECONDS = 30


class ApiError(Exception):
    def __init__(self, code, message, status=400):
        self.code, self.message, self.status = code, message, status


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def fail(code, message, status=400):
    raise ApiError(code, message, status)


def opaque():
    return secrets.token_urlsafe(32)


def token_header(request):
    header = request.headers.get('Authorization', '')
    if not header.startswith('Bearer ') or len(header) > 128:
        fail('unauthorized', 'Sign in again.', 401)
    return digest(header[7:])


def session_for(request):
    session = Session.objects.select_related('account').filter(token_hash=token_header(request), expires_at__gt=timezone.now()).first()
    if session is None:
        fail('unauthorized', 'Sign in again.', 401)
    require_beta_access(request, session.account_id)
    return session


def require_beta_access(request, account_id):
    if request.beta_policy['enabled'] and not BetaAccess.objects.filter(account_id=account_id, granted=True).exists():
        fail('beta_access_required', 'This account does not have closed beta access.', 403)


def require_release(request, release):
    if request.beta_policy['enabled'] and release != request.beta_policy['release_id']:
        fail('release_mismatch', 'Install the current closed beta release.', 409)


def locked_invite(request, body):
    if not request.beta_policy['enabled']:
        return None
    code = body.get('invite_code')
    if not isinstance(code, str) or not 1 <= len(code) <= 128:
        fail('invalid_invite', 'A valid unused beta invitation is required.', 403)
    invite = BetaInvite.objects.select_for_update().filter(code_hash=invite_digest(code)).first()
    if invite is None or invite.consumed_at is not None or invite.expires_at <= timezone.now():
        fail('invalid_invite', 'A valid unused beta invitation is required.', 403)
    return invite


def throttle(request, username):
    # Persistent limits cover restarts and every worker. Hash identifiers so database
    # maintenance does not expose submitted usernames or source IP addresses.
    window = int(time.time()) // 60
    keys = sorted([digest('ip:'+request.META.get('REMOTE_ADDR', 'unknown')),
                   digest('username:'+str(username).lower()[:100])])
    with transaction.atomic():
        for key in keys:
            limit, _ = RateLimit.objects.get_or_create(key=key, defaults={'window': window})
            limit = RateLimit.objects.select_for_update().get(pk=key)
            if limit.window != window:
                limit.window, limit.count = window, 0
            if limit.count >= 20:
                fail('rate_limited', 'Too many attempts. Try again shortly.', 429)
            limit.count += 1
            limit.save(update_fields=['window', 'count'])


def password_value(value):
    if not isinstance(value, str):
        return None
    value = unicodedata.normalize('NFC', value)
    if not 15 <= len(value) <= 128 or any(0xD800 <= ord(c) <= 0xDFFF for c in value):
        return None
    return value


def register(request, body):
    username = body.get('username')
    if not isinstance(username, str) or not re.fullmatch(r'[A-Za-z0-9_]{3,20}', username):
        fail('invalid_username', 'Use 3-20 ASCII letters, numbers, or underscores.')
    throttle(request, username)
    password = password_value(body.get('password'))
    if password is None:
        fail('invalid_password', 'Use 15-128 characters for your password.')
    if password != password_value(body.get('password_confirmation')):
        fail('password_mismatch', 'Passwords do not match.')
    if not HASH_SLOTS.acquire(blocking=False):
        fail('busy', 'Account service is busy. Try again shortly.', 503)
    try:
        encoded = make_password(password)
    finally:
        HASH_SLOTS.release()
    try:
        with transaction.atomic():
            invite = locked_invite(request, body)
            account = Account.objects.create(username=username, username_key=username.lower(), password_hash=encoded)
            character = Character.objects.create(account=account)
            if invite is not None:
                BetaAccess.objects.create(account=account, granted=True)
                invite.consumed_by = account
                invite.consumed_at = timezone.now()
                invite.save(update_fields=['consumed_by', 'consumed_at'])
    except IntegrityError:
        fail('username_unavailable', 'That username is unavailable.', 409)
    return {'ok': True, 'account_id': str(account.id), 'character_id': str(character.id)}


def login(request, body):
    username = body.get('username')
    throttle(request, username)
    valid_name = isinstance(username, str) and re.fullmatch(r'[A-Za-z0-9_]{3,20}', username)
    account = Account.objects.filter(username_key=username.lower()).first() if valid_name else None
    password = password_value(body.get('password'))
    if not HASH_SLOTS.acquire(blocking=False):
        fail('busy', 'Account service is busy. Try again shortly.', 503)
    try:
        valid = check_password(password or '', account.password_hash if account else DUMMY_HASH)
    finally:
        HASH_SLOTS.release()
    if not valid or account is None or password is None:
        fail('bad_credentials', 'Username or password is incorrect.', 401)
    token = opaque()
    with transaction.atomic():
        # Keep active session storage bounded per account and invalidate older sessions.
        Account.objects.select_for_update().get(pk=account.pk)
        require_beta_access(request, account.pk)
        Session.objects.filter(account=account).delete()
        Session.objects.create(token_hash=digest(token), account=account, expires_at=timezone.now()+timedelta(hours=12))
    return {'ok': True, 'token': token, 'account_id': str(account.id),
        'character_id': str(account.character.id), 'username': account.username}


def logout(request, body):
    session = session_for(request)
    session.delete()  # Cascades outstanding tickets. An active world must release its lease.
    return {'ok': True}


def character_summary(request, body):
    session = session_for(request)
    character = session.account.character
    return {'ok': True, 'account_id': str(session.account_id), 'character_id': str(character.id),
        'username': session.account.username, 'revision': character.revision,
        'initialized': bool(character.state), 'email_verified': session.account.email_verified_at is not None}


def world_value(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,80}', value):
        fail('invalid_world', 'Invalid world identifier.')
    return value


def admit(request, body):
    session = session_for(request)
    require_release(request, body.get('release_id'))
    world = world_value(body.get('world_id'))
    ticket = opaque()
    with transaction.atomic():
        # The account is always locked before sessions/tickets, matching login and
        # local grant/revoke so an authentication race cannot invert lock order.
        Account.objects.select_for_update().get(pk=session.account_id)
        if not Session.objects.select_for_update().filter(pk=session.pk, expires_at__gt=timezone.now()).exists():
            fail('unauthorized', 'Sign in again.', 401)
        require_beta_access(request, session.account_id)
        Admission.objects.filter(session=session).delete()
        Admission.objects.create(token_hash=digest(ticket), session=session, world_id=world,
            release_id=request.beta_policy.get('release_id', '') if request.beta_policy['enabled'] else '',
            expires_at=timezone.now()+timedelta(seconds=TICKET_SECONDS))
    return {'ok': True, 'ticket': ticket}


def internal_auth(request):
    expected = os.environ.get('AETHERIA_SERVER_KEY', '')
    provided = request.headers.get('X-Aetheria-Server-Key', '')
    if not expected or not hmac.compare_digest(expected.encode(), provided.encode()):
        fail('unauthorized', 'Server authentication required.', 401)


def claim(request, body):
    require_release(request, body.get('release_id'))
    ticket = body.get('ticket')
    world = world_value(body.get('world_id'))
    if not isinstance(ticket, str) or len(ticket) > 128:
        fail('invalid_ticket', 'Admission ticket is invalid or expired.', 401)
    with transaction.atomic():
        candidate = Admission.objects.filter(token_hash=digest(ticket)).values('session__account_id').first()
        if candidate is None:
            fail('invalid_ticket', 'Admission ticket is invalid or expired.', 401)
        Account.objects.select_for_update().get(pk=candidate['session__account_id'])
        admission = Admission.objects.select_for_update().filter(token_hash=digest(ticket)).first()
        now = timezone.now()
        if admission is None or admission.consumed or admission.expires_at <= now or admission.world_id != world:
            fail('invalid_ticket', 'Admission ticket is invalid or expired.', 401)
        require_release(request, admission.release_id)
        session = Session.objects.filter(pk=admission.session_id, expires_at__gt=now).first()
        if session is None:
            fail('invalid_ticket', 'Admission ticket is invalid or expired.', 401)
        require_beta_access(request, session.account_id)
        character = Character.objects.select_for_update().select_related('account').get(account_id=session.account_id)
        if character.lease_hash and character.lease_expires_at and character.lease_expires_at > now:
            fail('character_busy', 'This character is already in a world.', 409)
        lease = opaque()
        character.lease_generation += 1
        character.lease_hash = digest(lease)
        character.lease_world = world
        character.lease_expires_at = now+timedelta(seconds=LEASE_SECONDS)
        character.save(update_fields=['lease_generation', 'lease_hash', 'lease_world', 'lease_expires_at'])
        admission.consumed = True
        admission.save(update_fields=['consumed'])
        return {'ok': True, 'lease_token': lease, 'character_id': str(character.id),
            'account_id': str(character.account_id), 'username': character.account.username,
            'revision': character.revision, 'state': character.state}


def validate_state(state):
    if not isinstance(state, dict) or type(state.get('version')) is not int or state['version'] not in (1, 2):
        fail('invalid_state', 'Character state requires schema version 1 or 2.')
    nodes = 0

    def visit(value, depth=0):
        nonlocal nodes
        nodes += 1
        if nodes > 10000 or depth > 12:
            fail('invalid_state', 'Character state exceeds structural limits.')
        if isinstance(value, dict):
            if any(not isinstance(k, str) or len(k) > 128 for k in value):
                fail('invalid_state', 'Character state contains invalid keys.')
            for child in value.values():
                visit(child, depth+1)
        elif isinstance(value, list):
            for child in value:
                visit(child, depth+1)
        elif isinstance(value, str):
            if len(value) > 4096 or any(0xD800 <= ord(c) <= 0xDFFF for c in value):
                fail('invalid_state', 'Character state contains invalid text.')
        elif value is None or type(value) is bool:
            pass
        elif type(value) is int:
            if abs(value) > 9007199254740991:
                fail('invalid_state', 'Character state contains an oversized number.')
        elif type(value) is float and math.isfinite(value):
            pass
        else:
            fail('invalid_state', 'Character state contains an invalid value.')

    visit(state)
    serialized = json.dumps(state, ensure_ascii=True, sort_keys=True, separators=(',', ':'), allow_nan=False)
    if len(serialized.encode()) > 131072:
        fail('invalid_state', 'Character state is too large.')
    return serialized


def locked_character(body):
    try:
        character_id = uuid.UUID(str(body.get('character_id', '')))
    except (ValueError, TypeError, AttributeError):
        fail('invalid_character', 'Invalid character identifier.')
    character = Character.objects.select_for_update().filter(pk=character_id).first()
    if character is None:
        fail('invalid_character', 'Invalid character identifier.')
    return character


def check_lease(character, lease):
    if not isinstance(lease, str) or len(lease) > 128 or not character.lease_hash or not hmac.compare_digest(character.lease_hash, digest(lease)) or not character.lease_expires_at or character.lease_expires_at <= timezone.now():
        fail('stale_lease', 'Gameplay ownership has expired. Reconnect to continue.', 409)


def save(request, body, release=False):
    state = body.get('state')
    serialized = validate_state(state)
    revision = body.get('expected_revision')
    if type(revision) is not int or revision < 0 or revision > 9007199254740991:
        fail('invalid_revision', 'Invalid expected revision.')
    try:
        operation_id = uuid.UUID(str(body.get('operation_id', '')))
    except (ValueError, TypeError, AttributeError):
        fail('invalid_operation', 'An operation UUID is required.')
    lease = body.get('lease_token')
    if not isinstance(lease, str) or len(lease) > 128:
        fail('stale_lease', 'Gameplay ownership has expired. Reconnect to continue.', 409)
    payload_hash = digest(json.dumps([revision, release, serialized], separators=(',', ':')))
    with transaction.atomic():
        character = locked_character(body)
        prior = Journal.objects.filter(character=character, operation_id=operation_id).first()
        if prior:
            if not hmac.compare_digest(prior.lease_hash, digest(lease)):
                fail('stale_lease', 'Gameplay ownership has expired. Reconnect to continue.', 409)
            if prior.payload_hash != payload_hash:
                fail('operation_mismatch', 'Operation identifier was already used with different data.', 409)
            return {'ok': True, 'revision': prior.revision}
        check_lease(character, lease)
        if revision != character.revision:
            fail('revision_conflict', 'Character revision has changed.', 409)
        character.revision += 1
        character.state = state
        Journal.objects.create(character=character, operation_id=operation_id, payload_hash=payload_hash,
            lease_hash=character.lease_hash, lease_generation=character.lease_generation,
            revision=character.revision, state=state, released=release)
        if release:
            character.lease_hash = ''
            character.lease_world = ''
            character.lease_expires_at = None
        else:
            character.lease_expires_at = timezone.now()+timedelta(seconds=LEASE_SECONDS)
        character.save()
        return {'ok': True, 'revision': character.revision}


def heartbeat(request, body):
    with transaction.atomic():
        character = locked_character(body)
        check_lease(character, body.get('lease_token'))
        character.lease_expires_at = timezone.now()+timedelta(seconds=LEASE_SECONDS)
        character.save(update_fields=['lease_expires_at'])
    return {'ok': True}


def health(request, body):
    Character.objects.exists()
    return {'ok': True, 'service': 'aetheria-accounts', 'schema': 1}


def release_metadata(request, body):
    if not request.beta_policy['enabled']:
        return {'ok': True, 'enabled': False}
    return {'ok': True, **request.beta_policy}


def endpoint(request, route=''):
    try:
        try:
            local = ipaddress.ip_address(request.META.get('REMOTE_ADDR', '')).is_loopback
        except ValueError:
            local = False
        if not local and not request.is_secure():
            fail('https_required', 'HTTPS is required for remote account access.', 403)
        expected_method = 'GET' if route in ('api/character', 'api/release', 'health') else 'POST'
        if request.method != expected_method:
            fail('method_not_allowed', 'Unsupported request method.', 405)
        if len(request.body) > 262144:
            fail('request_too_large', 'Request is too large.', 413)
        body = {}
        if expected_method == 'POST':
            if request.content_type != 'application/json':
                fail('invalid_json', 'A JSON object is required.')
            try:
                body = json.loads(request.body)
            except (ValueError, UnicodeDecodeError, RecursionError):
                fail('invalid_json', 'A JSON object is required.')
            if not isinstance(body, dict):
                fail('invalid_json', 'A JSON object is required.')
        if route.startswith('internal/'):
            internal_auth(request)
        request.beta_policy = load_policy()
        routes = {'api/register': register, 'api/login': login, 'api/logout': logout,
            'api/character': character_summary, 'api/admit': admit, 'api/release': release_metadata,
            'internal/claim': claim, 'internal/save': save, 'internal/heartbeat': heartbeat,
            'internal/release': lambda r, b: save(r, b, release=True),
            'health': health}
        if route not in routes:
            fail('not_available', 'This account feature is not available.', 404)
        response = JsonResponse(routes[route](request, body))
    except BetaConfigError:
        response = JsonResponse({'ok': False, 'code': 'beta_unavailable', 'message': 'Beta admission is temporarily unavailable.'}, status=503)
    except RequestDataTooBig:
        response = JsonResponse({'ok': False, 'code': 'request_too_large', 'message': 'Request is too large.'}, status=413)
    except ApiError as error:
        response = JsonResponse({'ok': False, 'code': error.code, 'message': error.message}, status=error.status)
    except (OperationalError, IntegrityError):
        response = JsonResponse({'ok': False, 'code': 'service_unavailable', 'message': 'Account storage is temporarily unavailable. Retry shortly.'}, status=503)
    except Exception:
        # Do not let the framework log a traceback with submitted local variables.
        response = JsonResponse({'ok': False, 'code': 'internal_error', 'message': 'Account service could not complete the request.'}, status=500)
    response['Cache-Control'] = 'no-store'
    response['X-Content-Type-Options'] = 'nosniff'
    return response
