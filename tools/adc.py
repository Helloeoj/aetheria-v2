"""Local ADC report preparation and validated resolution. Python standard library only."""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

PROJECT = Path(__file__).resolve().parents[1]
GAME = PROJECT / "godot_client"


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def default_root():
    override = os.environ.get("AETHERIA_DIAGNOSTICS_DIR")
    if override:
        return Path(override).expanduser().resolve()
    config = (GAME / "project.godot").read_text(encoding="utf-8")
    name = re.search(r'^config/name="([^"]+)"', config, re.M).group(1)
    custom = re.search(r'^config/custom_user_dir_name="([^"]+)"', config, re.M)
    custom_on = "config/use_custom_user_dir=true" in config
    name = custom.group(1) if custom_on and custom else name
    if sys.platform == "win32":
        base = Path(os.environ["APPDATA"])
    elif sys.platform == "darwin":
        base = Path.home() / "Library/Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return (base / name if custom_on else base / "Godot/app_userdata" / name) / "diagnostics"


def read_json(path, fallback=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return fallback


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def alive(pid):
    if not isinstance(pid, int) or pid <= 0:
        return False
    if sys.platform == "win32":
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5  # Access denied is conservatively treated as live.
        try:
            code = ctypes.c_ulong()
            return not kernel.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value == 259
        finally:
            kernel.CloseHandle(handle)
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except ProcessLookupError:
        return False


def redact(text):
    return re.sub(r"(?i)(password|passwd|token|authorization|api[_-]?key|secret|cookie)\s*[:=]\s*[^\s,;]+", r"\1=[REDACTED]", text)


def compact(incident, detail):
    source = incident.get("source", {})
    context = incident.get("context", {})
    lines = ["AETHERIA DIAGNOSTIC REPORT",
             f"Incident: {incident['id']} | {incident['severity']} | occurrences: {incident['count']}",
             f"First: {incident['first_seen']} | Last: {incident['last_seen']}",
             f"Scene: {context.get('scene', 'unknown')} | System: {incident['system']}",
             "Error: " + incident['message'][:650],
             f"Source: {source.get('file', 'unavailable')}:{source.get('line', '?')} @ {source.get('function', 'unavailable')}",
             "Recent events (observed; proximity does not prove cause):"]
    for event in incident.get("recent_events", [])[-6:]:
        lines.append(f"- {event.get('system', '?')} / {event.get('action', '?')} {json.dumps(event.get('data', {}), ensure_ascii=False)[:160]}")
    if not incident.get("recent_events"):
        lines.append("- No gameplay breadcrumbs available.")
    lines.append("Context: " + json.dumps(context, ensure_ascii=False)[:350])
    files = list(dict.fromkeys([source.get("file", "unavailable")] + [f['file'] for f in incident.get('backtrace', []) if f.get('file', '').startswith('res://')]))[:5]
    lines.extend(["Relevant files (evidence locations): " + ", ".join(files),
                  "Evidence: " + incident.get("capture", "explicit report"),
                  "Hypothesis: None established. Inspect source and preceding actions first.",
                  "Reproduction: Not confirmed; resolution requires recorded validation.",
                  "Detailed JSON: " + str(detail),
                  "Native logs: " + str(incident.get("native_logs", []))])
    return "\n".join(lines) + "\n"


def native_evidence(meta, session):
    original = Path(meta.get("native_log", "__unavailable__"))
    candidates = []
    if original.is_file() and original.stat().st_mtime >= meta.get("started_unix", 0):
        candidates.append(original)
    if original.parent.is_dir():
        candidates += [p for p in original.parent.glob(original.stem + "*.log") if p != original and p.stat().st_mtime >= meta.get("started_unix", 0)]
    result = {"candidate_logs": [str(p) for p in candidates], "attribution": "candidate paths/timestamps; shared native logs may belong to a different process", "crash_signature_found": False}
    for candidate in candidates:
        with candidate.open("rb") as stream:
            stream.seek(max(0, candidate.stat().st_size - 1048576))
            tail = stream.read(1048576).decode("utf-8", errors="replace")
        if "Program crashed with signal" in tail or "Dumping the backtrace" in tail:
            saved = session / "recovered-native-tail.log"
            atomic(saved, tail)
            result.update(crash_signature_found=True, preserved_tail=str(saved), original_bytes=candidate.stat().st_size)
            break
    return result


def recover(root):
    for marker in sorted((root / "sessions").glob("*/session.json")):
        meta = read_json(marker, {})
        if not meta or meta.get("clean_shutdown") or meta.get("recovered_by") or alive(meta.get("pid")):
            continue
        identity = meta['session_id']
        stamp = now()
        fingerprint = hashlib.sha256(("suspected_termination:" + identity).encode()).hexdigest()
        incident = dict(schema_version=1, id="ADC-RECOVERY-" + identity, session_id=identity,
                        kind="suspected_termination", severity="ERROR", system="Session",
                        message="Suspected abnormal termination of session " + identity,
                        capture="missing clean-shutdown marker; not proof of a crash", source={}, backtrace=[],
                        fingerprint=fingerprint, count=1, first_seen=stamp, last_seen=stamp,
                        engine_version=meta.get('engine_version', 'unknown'), project_version=meta.get('project_version', 'unknown'),
                        context=meta.get('context', {}), recent_events=meta.get('recent_events', []),
                        details={"native_evidence": native_evidence(meta, marker.parent), "last_checkpoint": meta.get('checkpoint', 'unavailable')},
                        native_logs=[meta.get('native_log', 'unavailable')], related_incidents=[], samples=[])
        detail = marker.parent / "incidents" / (incident['id'] + ".json")
        atomic(detail, incident)
        atomic(detail.with_suffix(".txt"), compact(incident, detail))
        meta['recovered_by'] = "adc.py prepare " + stamp
        atomic(marker, meta)


def catalog(root):
    found, damaged = [], []
    for path in sorted((root / "sessions").glob("*/incidents/*.json")):
        data = read_json(path)
        if not isinstance(data, dict) or not {"id", "count", "fingerprint", "last_seen", "message"}.issubset(data):
            damaged.append(str(path))
            continue
        resolution = read_json(root / "resolutions" / (data['id'] + ".json"), {})
        resolved = bool(resolution) and resolution.get('occurrence_count', 0) >= data['count']
        found.append((path, data, resolved))
    found.sort(key=lambda row: (row[1]['last_seen'], row[1]['id']), reverse=True)
    return found, damaged


def prepare(root, quiet=False):
    root.mkdir(parents=True, exist_ok=True)
    recover(root)
    rows, damaged = catalog(root)
    unresolved = [(p, d) for p, d, resolved in rows if not resolved]
    history = [(p, d) for p, d, resolved in rows if resolved]
    for path, incident in unresolved:
        atomic(path.with_suffix('.txt'), compact(incident, path))
    atomic(root / "latest.txt", compact(unresolved[0][1], unresolved[0][0]) if unresolved else "No unresolved ADC incidents.\n")
    atomic(root / "unresolved.txt", "\n".join(str(path.with_suffix('.txt')) for path, _ in unresolved) + "\n")
    atomic(root / "resolved.txt", "\n".join(f"{data['id']} {root / 'resolutions' / (data['id'] + '.json')}" for _, data in history) + "\n")
    groups = {}
    for _, data, _ in rows:
        groups.setdefault(data['fingerprint'], []).append(data['id'])
    atomic(root / "catalog.json", {"schema_version": 1, "prepared": now(), "unresolved": len(unresolved), "resolved": len(history), "damaged_files": damaged, "related_incidents_by_fingerprint": {k: v for k, v in groups.items() if len(v) > 1}})
    if not quiet:
        print((root / "latest.txt").read_text(encoding="utf-8"), end="")
        if damaged:
            print(f"ADC: {len(damaged)} unreadable incident file(s); see catalog.json. Originals preserved.", file=sys.stderr)
    return rows


def resolve(root, identity, command, note):
    rows, _ = catalog(root)
    found = next(((p, d) for p, d, _ in rows if d['id'] == identity), None)
    if found is None:
        raise ValueError("Unknown incident ID; use 'prepare' or 'list'.")
    if not command:
        raise ValueError("Resolution requires --test followed by a real validation command.")
    _, incident = found
    # Record the count BEFORE testing. A recurrence during or after validation reopens the incident.
    count = incident['count']
    result = subprocess.run(command, cwd=PROJECT, capture_output=True, text=True, errors="replace", timeout=300)
    evidence = root / "resolutions" / (identity + ".validation.log")
    atomic(evidence, redact("COMMAND: " + repr(command) + "\n" + result.stdout + "\n" + result.stderr))
    if result.returncode != 0:
        raise ValueError(f"Validation failed ({result.returncode}); incident remains unresolved. Evidence: {evidence}")
    atomic(root / "resolutions" / (identity + ".json"), {"schema_version": 1, "incident_id": identity, "resolved_at": now(), "occurrence_count": count, "note": note, "validation": {"command": command, "exit_code": result.returncode, "evidence": str(evidence), "limitation": "Passing command recorded; agent must choose a test that actually covers the reported failure."}})
    prepare(root, quiet=True)
    print("Resolved with recorded passing validation: " + identity)


def import_log(root, log):
    """Explicit fallback for startup/parser failures before the autoload can register."""
    log = Path(log).resolve()
    identity = 'import-' + hashlib.sha256((str(log) + str(log.stat().st_mtime_ns)).encode()).hexdigest()[:20]
    session = root / 'sessions' / identity
    groups, current = {}, None

    def record(event):
        if not event:
            return
        normalized = re.sub(r'0x[0-9a-fA-F]+|(?i:instance[_ ]?id)[:= ]+[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+Z?', '<volatile>', event['message'])
        fingerprint = hashlib.sha256(json.dumps([normalized, event['source'], event['backtrace'][:8]], sort_keys=True).encode()).hexdigest()
        if fingerprint in groups:
            groups[fingerprint]['count'] += 1
            return
        if len(groups) >= 128:
            return  # Original log remains the complete source of evidence.
        stamp = now()
        event.update(schema_version=1, id='ADC-' + identity + '-' + fingerprint[:12], session_id=identity,
                     fingerprint=fingerprint, count=1, first_seen=stamp, last_seen=stamp,
                     severity='ERROR', system='Engine', kind='native_log_import',
                     capture='observed native log text; timestamps are import time; context unavailable',
                     engine_version='not recorded by importer', project_version='unknown',
                     context={}, recent_events=[], samples=[], related_incidents=[], native_logs=[str(log)])
        groups[fingerprint] = event

    with log.open(encoding='utf-8', errors='replace') as stream:
        for line in stream:
            match = re.match(r'^(?:SCRIPT ERROR|ERROR|USER ERROR):\s*(.*)', line)
            if match:
                record(current)
                current = {'message': redact(match.group(1))[:2048], 'source': {}, 'backtrace': []}
            elif current:
                frame = re.search(r'\[\d+\]\s+(.+?)\s+\((.+):(\d+)\)', line)
                origin = re.search(r'at:\s+(.+?)\s+\((.+):(\d+)\)', line)
                if frame and len(current['backtrace']) < 64:
                    current['backtrace'].append({'function': frame.group(1), 'file': frame.group(2).replace('\\', '/'), 'line': int(frame.group(3)), 'language': 'GDScript'})
                    current['source'] = current['backtrace'][0]
                elif origin and not current['source']:
                    current['source'] = {'function': origin.group(1), 'file': origin.group(2).replace('\\', '/'), 'line': int(origin.group(3))}
    record(current)
    if groups:
        atomic(session / 'session.json', dict(schema_version=1, session_id=identity, clean_shutdown=True, started=now(), pid=0, imported_log=str(log), native_log=str(log)))
        index = []
        for incident in groups.values():
            path = session / 'incidents' / (incident['id'] + '.json')
            atomic(path, incident)
            atomic(path.with_suffix('.txt'), compact(incident, path))
            index.append({k: incident[k] for k in ('id', 'last_seen', 'fingerprint', 'count')})
        atomic(session / 'index.json', index)
    return len(groups)


def run_game(root, engine, extra):
    if not engine:
        raise ValueError("Supply --godot or set GODOT to the installed executable.")
    # Unique native log avoids ambiguous attribution and concurrent-run rotation collisions.
    stamp = now().replace(":", "").replace("-", "") + "-" + str(os.getpid())
    native = root / "launches" / (stamp + ".log")
    native.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(root), AETHERIA_NATIVE_LOG=str(native))
    command = [engine, "--path", str(GAME), "--log-file", str(native), *extra]
    result = subprocess.run(command, env=env, cwd=PROJECT)
    atomic(native.with_suffix(".launch.json"), {"schema_version": 1, "ended": now(), "exit_code": result.returncode, "native_log": str(native), "command": command})
    started_adc = any(read_json(p, {}).get('native_log', '').replace('\\', '/') == str(native).replace('\\', '/') for p in (root / 'sessions').glob('*/session.json'))
    if not started_adc and native.exists():
        import_log(root, native)
    # Runtime fatal errors cannot execute GDScript cleanup. Prepare can recover their marker now.
    prepare(root, quiet=True)
    if result.returncode:
        print("Godot exited with code %s; report: %s" % (result.returncode, root / 'latest.txt'), file=sys.stderr)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=None, help='ADC storage override (default: Godot user://diagnostics)')
    parser.add_argument('--godot', default=os.environ.get('GODOT'), help='Installed Godot executable; never downloads/upgrades')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('prepare')
    sub.add_parser('paths')
    sub.add_parser('list')
    imported = sub.add_parser('import-log')
    imported.add_argument('log', type=Path)
    resolution = sub.add_parser('resolve')
    resolution.add_argument('incident')
    resolution.add_argument('--note', default='Validated by the recorded regression command.')
    resolution.add_argument('--test', nargs=argparse.REMAINDER, required=True)
    run = sub.add_parser('run')
    run.add_argument('args', nargs=argparse.REMAINDER)
    test = sub.add_parser('test')
    test.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = (args.root or default_root()).resolve()
    if args.command == 'paths':
        print(json.dumps({"storage": str(root), "latest": str(root / 'latest.txt'), "unresolved": str(root / 'unresolved.txt'), "resolved": str(root / 'resolved.txt'), "detailed": str(root / 'sessions'), "native_default": str(root.parent / 'logs'), "native_launcher": str(root / 'launches')}, indent=2))
    elif args.command == 'prepare':
        prepare(root)
    elif args.command == 'list':
        for path, data, resolved in prepare(root, quiet=True):
            print(f"{'RESOLVED' if resolved else 'OPEN'} {data['id']} x{data['count']} {data['message'][:100]} | {path}")
    elif args.command == 'import-log':
        print('Imported %d grouped incidents.' % import_log(root, args.log))
        prepare(root)
    elif args.command == 'resolve':
        resolve(root, args.incident, args.test, args.note)
    elif args.command == 'run':
        return run_game(root, args.godot, args.args[1:] if args.args[:1] == ['--'] else args.args)
    elif args.command == 'test':
        from test_adc import run_suite
        return run_suite(args.godot, args.output)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print('ADC: ' + str(error), file=sys.stderr)
        sys.exit(1)
