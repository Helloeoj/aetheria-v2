"""Independent, local-first ADC observer. UI-free model, usable in automated tests."""
from __future__ import annotations
from collections import deque
import hashlib
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import adc
from sentinel_windows import ProcessWatch, godot_pids, engine_processes, is_game, installed_engine, game_executable, HIDDEN


class LogTail:
    def __init__(self):
        self.path = None
        self.position = 0
        self.partial = b''
        self.signature = None
        self.lines = deque(maxlen=400)

    def read(self, path):
        path = Path(path) if path else None
        if path != self.path:
            self.path, self.position, self.partial, self.signature = path, 0, b'', None
            self.lines.clear()
        if path is None or not path.is_file():
            return []
        stat = path.stat()
        identity = stat.st_ino
        if self.signature != identity or stat.st_size < self.position:
            self.signature = identity
            self.position = max(0, stat.st_size - 65536)
            self.partial = b''
        if stat.st_size == self.position:
            return []
        skipped = stat.st_size - self.position > 65536
        if skipped:
            self.position = stat.st_size - 65536
            self.partial = b''
        with path.open('rb') as stream:
            stream.seek(self.position)
            data = stream.read(65536)
            self.position = stream.tell()
        parts = (self.partial + data).split(b'\n')
        self.partial = parts.pop()[-8192:]
        fresh = [adc.redact(p.decode('utf-8', errors='replace').rstrip('\r'))[:2048] for p in parts]
        if skipped:
            fresh.insert(0, '[Sentinel: log burst exceeded live-view budget; complete original remains on disk.]')
        self.lines.extend(fresh)
        return fresh


class Monitor:
    def __init__(self, root=None, discover=True):
        self.root = Path(root or adc.default_root()).resolve()
        self.project = adc.GAME
        self.discover = discover
        self.records = {}
        self.sessions = {}
        self.markers = {}
        self.active = {}
        self.activity = deque(maxlen=200)
        self.tail = LogTail()
        self.last_exit = None
        self.engine = installed_engine()
        self.last_signature = None
        self.seen_pids = set()
        self.notifications = queue.Queue(maxsize=2)
        self.commands = queue.Queue(maxsize=16)
        self.stop_event = threading.Event()
        self.thread = None
        self.revision = 0
        self.last_error = ''
        self._error_time = 0.0
        self._pending_save = False
        self._initial_prepared = False
        self.cleared_path = self.root / 'companion/cleared-incidents.json'
        saved = adc.read_json(self.cleared_path, {})
        self.cleared = saved if isinstance(saved, dict) else {}
        self._clear_revision = 0
        self.notice = ''
        self.last_exit = adc.read_json(self.root / 'companion/last-exit.json')
        self._restore_activity()
        self.event('READY', 'Sentinel started. Watching independently of the game.')

    def _restore_activity(self):
        saved = adc.read_json(self.root / 'companion/activity.json', [])
        if isinstance(saved, list):
            self.activity.extend(saved[-150:])

    def event(self, level, message):
        self.activity.append({'time': adc.now(), 'level': level, 'message': adc.redact(message)[:700]})
        self.revision += 1
        self._pending_save = True

    def enqueue(self, action, value=None):
        self.commands.put_nowait((action, value))

    def start(self):
        self.thread = threading.Thread(target=self._run, name='AetheriaSentinel', daemon=True)
        self.thread.start()

    def close(self):
        self.stop_event.set()
        # Never terminate or wait for a game child here. Closing Sentinel leaves Aetheria alone.

    def _run(self):
        while not self.stop_event.is_set():
            try:
                self.step()
                self.last_error = ''
            except Exception as error:
                detail = f'{type(error).__name__}: {error}'
                if detail != self.last_error or time.monotonic() - self._error_time > 30:
                    self.event('MONITOR', 'Monitor issue: ' + detail)
                    self._error_time = time.monotonic()
                self.last_error = detail
            self._publish()
            self.stop_event.wait(1.0)
        for record in self.active.values():
            record['watch'].close()

    def _publish(self):
        snapshot = self.snapshot()
        try:
            self.notifications.put_nowait(snapshot)
        except queue.Full:
            try:
                self.notifications.get_nowait()
            except queue.Empty:
                pass
            self.notifications.put_nowait(snapshot)

    def _attach(self, pid, session=None, native=None, launched=False):
        if pid in self.active:
            if session:
                self.active[pid]['session'] = session
            if native:
                self.active[pid]['native'] = str(native)
            return
        watch = ProcessWatch(pid)
        running, _ = watch.poll()
        if not running and not launched:
            watch.close()
            return
        self.active[pid] = {'pid': pid, 'watch': watch, 'session': session, 'native': str(native or ''), 'started': adc.now(), 'launched': launched}
        self.event('GAME', f'Aetheria started — PID {pid}. Live observation attached.')

    def _read_sessions(self):
        paths = list((self.root / 'sessions').glob('*/session.json'))
        current = set()
        for path in paths:
            current.add(path)
            stamp = path.stat().st_mtime_ns
            # A marker can arrive before process discovery. Reuse its cached
            # metadata so a later verified client links without waiting for a
            # checkpoint to rewrite the file.
            meta = (self.sessions.get(path.parent.name, {}) if self.markers.get(path) == stamp
                    else adc.read_json(path, {}))
            if not meta or not isinstance(meta, dict) or not meta.get('session_id'):
                continue
            self.markers[path] = stamp
            self.sessions[meta['session_id']] = meta
            pid = meta.get('pid', 0)
            if pid in self.active:
                self._attach(pid, meta['session_id'], meta.get('native_log'))
            elif os.name != 'nt' and pid and not meta.get('clean_shutdown') and not meta.get('recovered_by'):
                # Windows attaches only through verified process discovery (or
                # our own launch). A saved marker's live PID could be a server
                # or an unrelated process that reused an old client's PID.
                self._attach(pid, meta['session_id'], meta.get('native_log'))
        self.markers = {p: value for p, value in self.markers.items() if p in current}
        identities = {p.parent.name for p in current}
        self.sessions = {k: v for k, v in self.sessions.items() if k in identities}

    def _discover(self):
        if not self.discover:
            return
        pids = godot_pids()
        self.seen_pids.intersection_update(pids)
        new = pids - self.seen_pids
        if not new:
            return
        for process in engine_processes():
            pid = process.get('ProcessId')
            if pid not in new:
                continue
            executable = process.get('ExecutablePath')
            command = process.get('CommandLine')
            if not executable or not command:
                continue  # A process can appear before CIM exposes its details.
            self.seen_pids.add(pid)
            if executable and Path(executable).is_file() and not self.engine:
                self.engine = executable
            if not executable.lower().endswith('_console.exe') and is_game(command, self.project):
                self._attach(pid, native=self.root.parent / 'logs/godot.log')
        # Command lines are discarded; they are not persisted in reports/activity.

    def launch(self, engine=None, extra=None):
        engine = engine or self.engine
        if not engine or not Path(engine).is_file():
            raise ValueError('Choose the installed Godot executable first.')
        if self.active:
            raise ValueError('Aetheria is already running. Sentinel will keep observing it.')
        engine = game_executable(engine)
        self.engine = str(engine)
        name = 'sentinel-' + adc.now().replace(':', '').replace('-', '') + '-' + str(time.time_ns())
        native = self.root / 'launches' / (name + '.log')
        native.parent.mkdir(parents=True, exist_ok=True)
        environment = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(self.root), AETHERIA_NATIVE_LOG=str(native))
        command = [str(engine), '--path', str(self.project), '--log-file', str(native), *(extra or [])]
        child = subprocess.Popen(command, env=environment, cwd=adc.PROJECT, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=HIDDEN)
        self._attach(child.pid, native=native, launched=True)
        self.active[child.pid]['child'] = child  # Reaped after exit; never killed by the companion.
        return child.pid

    def _process_exit(self, record, exit_code):
        session = self.sessions.get(record.get('session'), {})
        if record.get('session'):
            marker = self.root / 'sessions' / record['session'] / 'session.json'
            session = adc.read_json(marker, session)
        clean = bool(session.get('clean_shutdown'))
        code = 'unavailable' if exit_code is None else (hex(exit_code) if exit_code > 65535 else str(exit_code))
        if clean and exit_code in (None, 0):
            status, level = 'Closed normally', 'CLOSED'
        elif clean:
            status, level = 'Exited with an error', 'ERROR'
        else:
            status, level = 'Unexpected stop', 'ATTENTION'
        self.last_exit = {'time': adc.now(), 'pid': record['pid'], 'code': exit_code, 'clean': clean, 'status': status}
        self.event(level, f'{status} — PID {record["pid"]}, exit {code}. ' + ('Clean shutdown marker present.' if clean else 'No clean shutdown marker; cause is not yet established.'))
        native = record.get('native')
        if native:
            self.tail.read(native)
            adc.atomic(self.root / 'companion/last-log-tail.txt', '\n'.join(self.tail.lines) + '\n')
        adc.prepare(self.root, quiet=True)
        if not session:
            imported = adc.import_log(self.root, native) if native and Path(native).is_file() else 0
            if not imported and not clean:
                self._external_incident(record, exit_code)
            adc.prepare(self.root, quiet=True)
        record['watch'].close()
        if 'child' in record:
            record['child'].poll()
        self.revision += 1

    def _external_incident(self, record, code):
        identity = 'observer-' + str(record['pid']) + '-' + str(time.time_ns())
        message = 'Observed game process exit without an ADC shutdown marker'
        fingerprint = hashlib.sha256((message + str(code)).encode()).hexdigest()
        incident = dict(schema_version=1, id='ADC-' + identity, session_id=identity, severity='ERROR', kind='process_exit',
                        system='Process', message=message, fingerprint=fingerprint, source={}, backtrace=[], context={'project': str(self.project)},
                        recent_events=[], samples=[], related_incidents=[], count=1, first_seen=adc.now(), last_seen=adc.now(),
                        engine_version='unavailable', project_version='unknown', native_logs=[record['native']] if record['native'] else [],
                        capture='external process observation; missing marker is not proof of a crash',
                        details={'pid': record['pid'], 'observed_exit_code': code, 'started': record['started']})
        base = self.root / 'sessions' / identity
        adc.atomic(base / 'session.json', {'schema_version': 1, 'session_id': identity, 'pid': 0, 'clean_shutdown': True, 'started': adc.now(), 'observer_record': True})
        detail = base / 'incidents' / (incident['id'] + '.json')
        adc.atomic(detail, incident)
        adc.atomic(detail.with_suffix('.txt'), adc.compact(incident, detail))
        adc.atomic(base / 'index.json', [{k: incident[k] for k in ('id', 'last_seen', 'count', 'fingerprint')}])

    def _read_incidents(self):
        paths = list((self.root / 'sessions').glob('*/incidents/*.json'))
        keys = set()
        for path in paths:
            keys.add(path)
            stamp = path.stat().st_mtime_ns
            receipt = self.root / 'resolutions' / (path.stem + '.json')
            signature = (stamp, receipt.stat().st_mtime_ns if receipt.is_file() else 0, self._clear_revision)
            previous = self.records.get(path)
            if previous and previous['signature'] == signature:
                continue
            incident = adc.read_json(path)
            if not isinstance(incident, dict) or not {'id', 'message', 'count', 'severity', 'last_seen'}.issubset(incident):
                continue
            resolution = adc.read_json(receipt, {})
            resolved = bool(resolution) and resolution.get('occurrence_count', 0) >= incident['count']
            marker = self.cleared.get(incident['id'], {})
            cleared = (isinstance(marker, dict)
                       and marker.get('occurrence_count') == incident['count']
                       and marker.get('last_seen') == incident['last_seen'])
            self.records[path] = {'path': str(path), 'data': incident, 'resolved': resolved, 'resolution': resolution, 'signature': signature, 'cleared': cleared}
            if previous is None:
                from sentinel_explanations import incident_title
                self.event('INCIDENT', incident_title(incident))
            self.revision += 1
        self.records = {p: row for p, row in self.records.items() if p in keys}

    def clear_results(self, observed):
        """Acknowledge only occurrences the user saw; retain evidence and fix receipts."""
        known = {row['data']['id'] for row in self.records.values()}
        updated = {identity: marker for identity, marker in self.cleared.items() if identity in known}
        count = 0
        for entry in observed or []:
            if (not isinstance(entry, dict) or entry.get('id') not in known
                    or not isinstance(entry.get('occurrence_count'), int)
                    or entry['occurrence_count'] < 1 or not isinstance(entry.get('last_seen'), str)):
                continue
            updated[entry['id']] = {'occurrence_count': entry['occurrence_count'],
                                    'last_seen': entry['last_seen'], 'cleared_at': adc.now()}
            count += 1
        if not count:
            return
        # Commit before changing the cached view, so a failed save leaves results visible.
        adc.atomic(self.cleared_path, updated)
        self.cleared = updated
        self._clear_revision += 1
        self.notice = f'Cleared {count} results. New occurrences will appear automatically.'
        self.event('CLEARED', f'Cleared {count} incident results from the current view. Saved reports remain in All retained.')

    def step(self):
        if not self._initial_prepared:
            adc.prepare(self.root, quiet=True)
            self._initial_prepared = True
        while not self.commands.empty():
            action, value = self.commands.get_nowait()
            try:
                if action == 'launch':
                    self.launch(value)
                elif action == 'prepare':
                    adc.prepare(self.root, quiet=True)
                    self.event('READY', 'Reports refreshed. Compact evidence is ready to copy.')
                elif action == 'import':
                    count = adc.import_log(self.root, value)
                    adc.prepare(self.root, quiet=True)
                    self.event('READY', f'Imported {count} grouped native-log incidents.')
                elif action == 'clear':
                    self.clear_results(value)
            except Exception as error:
                self.event('ATTENTION', str(error))
                if action == 'clear':
                    self.notice = 'Could not clear results: ' + str(error)
        self._discover()
        self._read_sessions()
        for pid, record in list(self.active.items()):
            running, code = record['watch'].poll()
            if not running:
                self._process_exit(record, code)
                del self.active[pid]
        if self.active:
            record = list(self.active.values())[-1]
            if record['native']:
                self.tail.read(record['native'])
        elif self.tail.path is None and self.sessions:
            newest = max(self.sessions.values(), key=lambda s: s.get('started', ''))
            self.tail.read(newest.get('native_log'))
        self._read_incidents()
        if self._pending_save:
            adc.atomic(self.root / 'companion/activity.json', list(self.activity))
            if self.last_exit:
                adc.atomic(self.root / 'companion/last-exit.json', self.last_exit)
            self._pending_save = False

    def snapshot(self):
        rows = sorted(self.records.values(), key=lambda r: (r['data']['last_seen'], r['data']['id']), reverse=True)
        return {'revision': self.revision, 'active': [{k: v for k, v in record.items() if k in ('pid', 'session', 'native', 'started')} for record in self.active.values()],
                'incidents': rows, 'open_count': sum(not row['resolved'] and not row['cleared'] for row in rows), 'activity': list(self.activity),
                'log': list(self.tail.lines), 'log_path': str(self.tail.path or ''), 'last_exit': self.last_exit,
                'engine': self.engine, 'error': self.last_error, 'notice': self.notice}
