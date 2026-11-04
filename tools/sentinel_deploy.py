"""Manual Sentinel deployment through the existing private beta release pipeline.

Preview/status are read-only. update() blocks while server.ps1 builds, audits,
publishes and gracefully activates its matching release; callers use a worker.
"""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
from urllib.parse import urlsplit, urlunsplit
import uuid

import beta_ops
import beta_package
import beta_release
import server_ops

HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
_RELEASE = re.compile(r'[A-Za-z0-9_.-]{1,80}')
_PRIVATE_KEY = re.compile(r'password|token|secret|credential|api.?key', re.I)


def _read(path):
    try:
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def _same_path(left, right):
    return os.path.normcase(str(Path(left).resolve())) == os.path.normcase(str(Path(right).resolve()))


class DeploymentController:
    def __init__(self, repo: Path, data: Path):
        self.repo = Path(repo).resolve()
        self.data = Path(data).resolve()
        self.runtime = self.data / 'beta-runtime'
        self._busy = threading.Lock()

    def _source(self):
        result = {'branch': '', 'commit': '', 'changed_files': 0, 'summary': [],
                  'description': 'Saved local project, including uncommitted changes.'}
        try:
            def git(*args):
                return subprocess.run(['git', *args], cwd=self.repo, capture_output=True,
                    text=True, encoding='utf-8', errors='replace', timeout=6,
                    creationflags=HIDDEN, check=True).stdout
            result['branch'] = git('branch', '--show-current').strip()[:160]
            result['commit'] = git('rev-parse', '--short=12', 'HEAD').strip()[:40]
            entries = iter(git('status', '--porcelain=v1', '-z', '--untracked-files=normal').split('\0'))
            for entry in entries:
                if not entry:
                    continue
                result['changed_files'] += 1
                if len(result['summary']) < 20:
                    result['summary'].append(re.sub(r'[\x00-\x1f\x7f]', '?', entry)[:240])
                if 'R' in entry[:2] or 'C' in entry[:2]:
                    next(entries, None)
        except (OSError, subprocess.SubprocessError):
            result['description'] += ' Git summary unavailable.'
        return result

    def _engine(self, engine):
        candidate = engine or os.environ.get('GODOT') or shutil.which('godot')
        if not candidate:
            directory = Path(os.environ.get('USERPROFILE', str(Path.home()))) / 'Downloads/Godot'
            candidate = next(directory.glob('*4.5.1*console.exe'), None)
        return str(Path(candidate).resolve()) if candidate else ''

    def preview(self, engine=None):
        settings = _read(self.runtime / 'hosting.json')
        policy = _read(self.data / 'beta.json')
        profile = _read(self.runtime / 'client-profile.json')
        launcher = _read(self.runtime / 'launcher.json')
        release = policy.get('release_id', '')
        release = release if isinstance(release, str) and _RELEASE.fullmatch(release) else ''
        target = {}
        valid_hosting = False
        try:
            public = beta_ops.public_profile(settings, release or 'preview')
            beta_package.validate_profile(public)
            valid_hosting = (settings.get('schema') == 1 and bool(settings.get('owner_username'))
                and type(settings.get('upload_id')) is int and settings['upload_id'] > 0)
            if valid_hosting:
                target = {key: public[key] for key in ('account_url', 'world_host', 'world_port', 'world_id')}
        except (ValueError, KeyError, TypeError, AttributeError):
            pass
        valid_profile = False
        try:
            beta_package.validate_profile(profile)
            valid_profile = bool(target) and all(profile.get(key) == value for key, value in target.items())
        except (ValueError, KeyError, TypeError, AttributeError):
            pass
        valid_launcher = (launcher.get('schema') == 1 and bool(launcher.get('oauth_client_id'))
            and type(launcher.get('game_id')) is int and launcher['game_id'] > 0
            and launcher.get('upload_id') == settings.get('upload_id')
            and launcher.get('account_url') == target.get('account_url')
            and launcher.get('executable') == 'Aetheria.exe'
            and launcher.get('download_bytes_per_second') == 500000)
        engine_path = self._engine(engine)
        prerequisites = []
        def check(name, ok, detail):
            prerequisites.append({'name': name, 'ok': bool(ok), 'detail': detail})
        check('Live beta policy', policy.get('enabled') is True and bool(release),
              'An enabled beta release is required for publishing and activation.')
        check('Public hosting', valid_hosting, 'Existing private hosting configuration and public target are required.')
        check('Tester profile', valid_profile, 'The saved tester profile must match this public target.')
        check('Launcher channel', valid_launcher, 'The existing launcher must match the private beta upload and account endpoint.')
        check('Godot engine', bool(engine_path) and Path(engine_path).is_file(), 'An installed Godot console executable is required.')
        check('Release scripts', all((self.repo / 'tools' / name).is_file() for name in
              ('server.ps1', 'beta_release.py', 'beta_ops.py', 'beta_package.py', 'server_ops.py')),
              'The existing build, audit, publish and graceful activation pipeline must be installed.')
        check('Private Python', (self.data / 'venv/Scripts/python.exe').is_file(), 'The installed account service Python runtime is required.')
        helper_keys = ('cloudflared', 'node', 'wrangler', 'worker_config', 'playit', 'playit_secret')
        check('Hosting tools', all(isinstance(settings.get(key), str) and Path(settings[key]).is_file()
              for key in helper_keys), 'Existing tunnel, relay and edge deployment tools must be installed.')
        check('Publisher and certificates', all((self.runtime / name).is_file() for name in
              ('butler/butler.exe', 'itch-publisher-creds', 'world-public.crt', 'world-private.key')),
              'The existing private publisher identity and TLS material must be available.')
        check('Release recovery', not any((self.runtime / name).exists() for name in
              ('release.lock', 'activation.pending', 'sentinel-update.lock')) and not self._busy.locked(),
              'Another update or an interrupted activation must be resolved before updating.')
        actual_data = Path(os.environ.get('LOCALAPPDATA', '')) / 'Aetheria/online'
        account_data = os.environ.get('AETHERIA_ACCOUNT_DATA')
        check('Runtime target', _same_path(actual_data, self.data) and not self.data.is_relative_to(self.repo)
              and (not account_data or _same_path(account_data, self.data)),
              'World and account services must use the same private Windows runtime; remove a conflicting AETHERIA_ACCOUNT_DATA override.')
        return {'eligible': all(item['ok'] for item in prerequisites),
                'mode': 'beta-live' if policy.get('enabled') is True and valid_hosting else 'unconfigured',
                'target': target, 'current_release': release, 'source': self._source(),
                'prerequisites': prerequisites, 'engine': engine_path}

    def status(self):
        policy = _read(self.data / 'beta.json')
        release = policy.get('release_id', '')
        release = release if isinstance(release, str) and _RELEASE.fullmatch(release) else ''
        checks = dict.fromkeys(('selection', 'world_ready', 'process_identity', 'ingress'), False)
        result = {'ok': False, 'state': 'unconfigured', 'release_id': release, 'world_id': '',
                  'message': 'Live beta hosting is not configured.', 'checks': checks,
                  'updating': self._busy.locked() or (self.runtime / 'sentinel-update.lock').exists()
                              or (self.runtime / 'release.lock').exists()}
        if policy.get('enabled') is not True or not release:
            return result
        result.update(state='mismatch', message='The selected client/server release could not be verified.')
        try:
            selected = _read(self.data / 'server-build.json')
            if not _same_path(selected['repo'], self.repo):
                return result
            server_ops.validate_startup(self.data)
            client = beta_release.verify_client(self.data / 'beta-builds' / release, release)
            pair = _read(self.data / 'beta-builds' / (release + '-validation') / 'release-candidate.json')
            if pair.get('client') != client:
                return result
            checks['selection'] = True
            world = _read(self.data / 'world.json')
            world_id = world.get('world_id', '')
            if isinstance(world_id, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,64}', world_id):
                result['world_id'] = world_id
            ready_path = self.data / 'world-ready.json'
            ready = _read(ready_path)
            checks['world_ready'] = bool(result['world_id']) and ready.get('world_id') == world_id \
                and ready.get('port') == world.get('port') and type(ready.get('pid')) is int
            identity = beta_ops.process_identity(ready['pid']) if checks['world_ready'] else None
            checks['process_identity'] = bool(identity and _same_path(identity['exe'], selected['exe'])
                and type(identity.get('created')) is int and identity['created'] > 0
                and identity['created'] / 10_000_000 - 11_644_473_600 <= ready_path.stat().st_mtime + 2)
            records = _read(self.data / 'beta-processes.json')
            active = _read(self.data / 'beta-active.json')
            checks['ingress'] = active.get('release_id') == release and all(
                beta_ops.matches(records.get(name)) for name in beta_ops.SERVICES)
            if all(checks.values()):
                result.update(ok=True, state='running', message='Matching beta release and live world process verified.')
            elif not checks['world_ready'] or not checks['process_identity']:
                result.update(state='stopped', message='No ready world process for the selected beta release was verified.')
            else:
                result.update(state='stopped', message='World is ready; public ingress for this release is not verified.')
        except (OSError, ValueError, KeyError, TypeError, AttributeError, RuntimeError):
            pass
        return result

    def _redactor(self):
        secrets = set()
        def collect(value, all_strings=False):
            if isinstance(value, dict):
                for key, item in value.items():
                    collect(item, all_strings or bool(_PRIVATE_KEY.search(str(key))))
            elif isinstance(value, list):
                for item in value:
                    collect(item, all_strings)
            elif all_strings and isinstance(value, str) and len(value) >= 4:
                secrets.add(value)
        for name in ('config.json', 'ingress.json', 'beta-runtime/hosting.json'):
            collect(_read(self.data / name))
        for name in ('itch-publisher-creds', 'playit-secret-assignable', 'playit-secret-legacy'):
            path = self.runtime / name
            try:
                value = path.read_text(encoding='utf-8-sig').strip()
                try:
                    collect(json.loads(value), True)
                except ValueError:
                    if len(value) >= 4:
                        secrets.add(value)
            except OSError:
                pass
        def redact(line):
            line = str(line)
            for secret in sorted(secrets, key=len, reverse=True):
                line = line.replace(secret, '[redacted]')
            line = re.sub(r'(?i)(bearer\s+)\S+', r'\1[redacted]', line)
            line = re.sub(r'(?i)((?:password|token|secret|credential|api[_-]?key)[\w-]*[\s\"\x27]*[:=]\s*)[^\s,;]+',
                          r'\1[redacted]', line)
            def safe_url(match):
                try:
                    url = urlsplit(match.group())
                    return urlunsplit((url.scheme, (url.hostname or '') + (f':{url.port}' if url.port else ''),
                                       url.path, '', ''))
                except ValueError:
                    return '[redacted URL]'
            return re.sub(r'https?://[^\s<>\"\x27]+', safe_url, line).rstrip('\r\n')
        return redact

    def update(self, engine, emit):
        """Run once after user review. Never retry, change Git state or force-stop a world."""
        final_status = None
        def failure(message, code=None, log=''):
            nonlocal final_status
            state = self.status()
            final_status = state
            return {'ok': False, 'returncode': code, 'message': message,
                    'release_id': state['release_id'], 'log_path': log, 'status': state}
        if not self._busy.acquire(blocking=False):
            return failure('A Sentinel live update is already running.')
        lock = self.runtime / 'sentinel-update.lock'
        owns_lock, child, finished, log_path, redact = False, None, False, '', None
        try:
            # The local mutex is already held; preview's recovery check includes it.
            preview = self.preview(engine)
            blocked = [item['name'] for item in preview['prerequisites'] if not item['ok']
                       and item['name'] != 'Release recovery']
            if any((self.runtime / name).exists() for name in ('release.lock', 'activation.pending', 'sentinel-update.lock')):
                blocked.append('Release recovery')
            if blocked:
                return failure('Update unavailable: ' + ', '.join(blocked) + '.')
            with lock.open('x', encoding='utf-8') as handle:
                owns_lock = True
                json.dump({'pid': os.getpid()}, handle)
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
            path = self.runtime / ('sentinel-deploy-' + stamp + '-' + uuid.uuid4().hex[:8] + '.log')
            log_path = str(path)
            redact = self._redactor()
            with path.open('x', encoding='utf-8') as transcript:
                def report(line):
                    clean = redact(line)
                    transcript.write(clean + '\n')
                    transcript.flush()
                    try:
                        emit(clean)
                    except Exception:
                        # Closing a UI must not abandon or interrupt an in-flight release.
                        pass
                report('Building the saved local project, including uncommitted changes.')
                environment = dict(os.environ, GODOT=preview['engine'], PYTHONUNBUFFERED='1')
                child = subprocess.Popen(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                    '-File', str(self.repo / 'tools/server.ps1'), 'build'], cwd=self.repo,
                    env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL, text=True, encoding='utf-8', errors='replace',
                    bufsize=1, creationflags=HIDDEN)
                try:
                    for line in child.stdout:
                        report(line)
                    code = child.wait()
                    finished = True
                finally:
                    child.stdout.close()
                state = self.status()
                final_status = state
                ok = code == 0 and state['ok'] and state['release_id'] != preview['current_release']
                message = ('Matching client/server update published and its live world verified.' if ok
                           else f'Update failed with exit code {code}. Inspect the private deployment log.' if code
                           else 'Build returned success, but a new live release could not be verified. Inspect the private deployment log.')
                report(message)
                return {'ok': ok, 'returncode': code, 'message': message,
                        'release_id': state['release_id'], 'log_path': log_path, 'status': state}
        except FileExistsError:
            return failure('Another live update is running or needs recovery; no update was started.', log=log_path)
        except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as error:
            if log_path and redact:
                clean = redact(type(error).__name__ + ': ' + str(error))
                try:
                    with Path(log_path).open('a', encoding='utf-8') as transcript:
                        transcript.write(clean + '\n')
                    emit(clean)
                except Exception:
                    pass
            return failure('The update could not be completed. Inspect the private deployment log; no automatic retry was made.', log=log_path)
        finally:
            # If streaming failed while the pipeline may still be running, leave
            # the marker for operator recovery instead of allowing a duplicate.
            if owns_lock and (child is None or finished):
                lock.unlink(missing_ok=True)
            self._busy.release()
            if final_status is not None:
                final_status['updating'] = self._busy.locked() or lock.exists() or (self.runtime / 'release.lock').exists()
