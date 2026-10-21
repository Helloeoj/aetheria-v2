"""Headless end-to-end ADC regression suite. Output is isolated from real game incidents."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import adc


def run_suite(engine, output=None):
    if not engine:
        raise ValueError('Supply --godot or set GODOT to the existing Godot executable.')
    output = Path(output or tempfile.mkdtemp(prefix='aetheria-adc-test-')).resolve()
    output.mkdir(parents=True, exist_ok=True)
    checks = []

    def check(condition, label):
        checks.append(dict(test=label, passed=bool(condition)))
        print(('PASS ' if condition else 'FAIL ') + label, flush=True)

    def launch(name, scene='res://diagnostics/probe.tscn', mode='once', root=None, extra=None, enabled=True, wait=True):
        root = Path(root or output / name)
        native = output / (name + '.native.log')
        console = output / (name + '.console.log')
        env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(root), AETHERIA_NATIVE_LOG=str(native), AETHERIA_DIAGNOSTICS='1' if enabled else '0')
        command = [engine, '--headless', '--path', str(adc.GAME), '--log-file', str(native)]
        if scene:
            command.append(scene)
        command += (extra or [])
        command += ['--', '--probe=' + mode]
        stream = console.open('w', encoding='utf-8')
        child = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT, cwd=adc.PROJECT)
        if not wait:
            return child, stream, root, console
        try:
            code = child.wait(timeout=60)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
            raise ValueError(f'{name} timed out; inspect {console}')
        finally:
            stream.close()
        return code, root, console

    def markers(root):
        return [adc.read_json(p, {}) for p in (root / 'sessions').glob('*/session.json')]

    code, root, console = launch('runtime', scene='res://diagnostics/test_diagnostics.tscn')
    result = adc.read_json(root / 'test-result.json', {})
    check(code == 0 and result.get('checks', 0) >= 20 and result.get('failures') == [], 'native capture + breadcrumbs + grouping + real equipment regression (20 assertions)')
    check(bool(markers(root)) and all(m.get('clean_shutdown') for m in markers(root)), 'normal process shutdown persists clean marker')
    check('SCRIPT ERROR: Parse Error' not in console.read_text(encoding='utf-8'), 'new scripts parse in installed engine')
    rows = adc.prepare(root, quiet=True)
    check(bool(rows) and (root / 'latest.txt').stat().st_size < 4000, 'offline preparation produces compact latest report')
    schema = adc.read_json(adc.GAME / 'diagnostics/incident.schema.json')
    check(all(set(schema['required']).issubset(d) and d['schema_version'] == 1 and len(d['backtrace']) <= 64 and len(d['samples']) <= 4 for _, d, _ in rows), 'incident schema required fields/version and evidence bounds are stable')

    # Real killed test process; never kill the user's editor or a game process we did not launch.
    child, stream, recovery_root, console = launch('abnormal', mode='hold', wait=False)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and child.poll() is None:
            if 'ADC PROBE READY' in console.read_text(encoding='utf-8', errors='replace'):
                break
            time.sleep(0.1)
        ready = 'ADC PROBE READY' in console.read_text(encoding='utf-8', errors='replace')
        child.kill()
        child.wait(timeout=10)
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        stream.close()
    check(ready and any(not m.get('clean_shutdown') for m in markers(recovery_root)), 'terminated isolated process leaves unclean marker and persisted earlier evidence')
    code, _, _ = launch('restarted', root=recovery_root)
    recovered = [d for _, d, _ in adc.catalog(recovery_root)[0] if d.get('kind') == 'suspected_termination']
    check(code == 0 and len(recovered) == 1 and 'not proof' in recovered[0]['capture'], 'restart creates exactly one suspected-termination incident')
    code, _, _ = launch('restarted_again', root=recovery_root)
    check(len([d for _, d, _ in adc.catalog(recovery_root)[0] if d.get('kind') == 'suspected_termination']) == 1, 'recovery does not repeat on subsequent restarts')

    child, stream, offline_root, console = launch('offline_abnormal', mode='hold', wait=False)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and child.poll() is None:
            if 'ADC PROBE READY' in console.read_text(encoding='utf-8', errors='replace'):
                break
            time.sleep(0.1)
        check(adc.alive(child.pid), 'offline process check recognizes live test process')
        adc.prepare(offline_root, quiet=True)
        check(not any(d.get('kind') == 'suspected_termination' for _, d, _ in adc.catalog(offline_root)[0]), 'live parallel process is not classified as abnormal')
        child.kill()
        child.wait(timeout=10)
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        stream.close()
    adc.prepare(offline_root, quiet=True)
    check(any(d.get('kind') == 'suspected_termination' for _, d, _ in adc.catalog(offline_root)[0]), 'offline prepare recovers without launching the game')

    fault = output / 'file-instead-of-directory'
    fault.write_text('intentional storage failure fixture', encoding='utf-8')
    code, _, _ = launch('disk_fault', root=fault, mode='fault')
    check(code == 0, 'storage failure latches without recursive diagnostic errors or breaking gameplay')
    code, disabled_root, _ = launch('disabled', mode='disabled', enabled=False)
    check(code == 0 and not disabled_root.exists(), 'disabled diagnostics are no-op and create no session/output')
    code, _, _ = launch('scene_failure', mode='scene_failure')
    check(code == 0, 'failed scene transition is explicitly diagnosed')
    code, overflow_root, _ = launch('overflow', mode='overflow')
    check(code == 0 and sum(m.get('dropped_occurrences', 0) for m in markers(overflow_root)) == 172, 'unique error flood stays bounded with exact overflow count')

    rotation_root = output / 'retention'
    for index in range(22):
        fixture = rotation_root / 'sessions' / ('fixture-%02d' % index)
        adc.atomic(fixture / 'session.json', {'schema_version': 1, 'session_id': fixture.name, 'pid': 2000000000, 'clean_shutdown': True, 'started': '2000-01-%02dT00:00:00Z' % (index + 1)})
        adc.atomic(fixture / 'incidents' / 'fixture.txt', 'old ADC fixture')
    code, _, _ = launch('retention', root=rotation_root)
    check(code == 0 and len(list((rotation_root / 'sessions').iterdir())) == 16 and (rotation_root / 'retention.json').is_file(), 'session rotation removes oldest closed evidence and records retention')
    byte_root = output / 'byte_retention'
    for index in range(2):
        fixture = byte_root / 'sessions' / ('large-fixture-%d' % index)
        adc.atomic(fixture / 'session.json', {'schema_version': 1, 'session_id': fixture.name, 'pid': 2000000000, 'clean_shutdown': True, 'started': '2000-01-01T00:00:00Z'})
        with (fixture / 'large-fixture.log').open('wb') as stream:
            stream.truncate(34 * 1048576)
    code, _, _ = launch('byte_retention', root=byte_root)
    check(code == 0 and (byte_root / 'retention.json').is_file() and adc.read_json(byte_root / 'retention.json')['remaining_bytes'] <= 64 * 1048576, 'storage byte budget rotates old closed evidence')

    fixture_root = output / 'native_signature_fixture'
    fixture = fixture_root / 'sessions' / 'synthetic-native-signature'
    fake_log = output / 'LABELLED-FAKE-NATIVE-CRASH.log'
    fake_log.write_text('SYNTHETIC FIXTURE: NO NATIVE CRASH OCCURRED\nProgram crashed with signal 11\nDumping the backtrace.\n[0] synthetic fixture only\n', encoding='utf-8')
    adc.atomic(fixture / 'session.json', {'schema_version': 1, 'session_id': fixture.name, 'pid': 2000000000, 'clean_shutdown': False, 'started': '2000-01-01T00:00:00Z', 'started_unix': 0, 'native_log': str(fake_log)})
    code, _, _ = launch('native_signature_fixture', root=fixture_root)
    recovery = [d for _, d, _ in adc.catalog(fixture_root)[0] if d.get('kind') == 'suspected_termination']
    check(code == 0 and len(recovery) == 1 and recovery[0]['details']['native_evidence'].get('crash_signature_found') and (fixture / 'recovered-native-tail.log').is_file(), 'labelled fake native-crash signature is detected and preserved after restart')

    imported_root = output / 'imported_startup_fixture'
    startup_log = output / 'LABELLED-FAKE-STARTUP-ERROR.log'
    startup_log.write_text('SYNTHETIC STARTUP FIXTURE\nSCRIPT ERROR: Parse Error: Unknown identifier in startup fixture.\n   at: GDScript::reload (res://diagnostics/fake_fixture.gd:42)\nSCRIPT ERROR: Parse Error: Unknown identifier in startup fixture.\n   at: GDScript::reload (res://diagnostics/fake_fixture.gd:42)\n', encoding='utf-8')
    imported = adc.import_log(imported_root, startup_log)
    adc.import_log(imported_root, startup_log)
    imported_rows = adc.prepare(imported_root, quiet=True)
    check(imported == 1 and len(imported_rows) == 1 and imported_rows[0][1]['count'] == 2 and imported_rows[0][1]['source']['line'] == 42, 'startup fallback imports exact native evidence, groups duplicates, and is idempotent')

    # Resolution is evidence gated; a new occurrence automatically reopens the same incident.
    path, incident, _ = rows[0]
    refused = False
    try:
        adc.resolve(root, incident['id'], [sys.executable, '-c', 'raise SystemExit(1)'], 'must fail')
    except ValueError:
        refused = True
    check(refused and not (root / 'resolutions' / (incident['id'] + '.json')).exists(), 'failed validation cannot resolve an incident')
    validation = [engine, '--version']  # Tests state transitions only; not a claim of fixing a game bug.
    adc.resolve(root, incident['id'], validation, 'Synthetic resolution workflow test only; engine version checks harness command execution.')
    check(any(d['id'] == incident['id'] and resolved for _, d, resolved in adc.catalog(root)[0]), 'passing command and evidence are recorded in resolved history')
    incident['count'] += 1
    adc.atomic(path, incident)
    adc.prepare(root, quiet=True)
    check(any(d['id'] == incident['id'] and not resolved for _, d, resolved in adc.catalog(root)[0]), 'recurrence reopens a previously resolved incident')
    adc.atomic(root / 'sessions' / 'damaged' / 'incidents' / 'broken.json', '{broken')
    adc.prepare(root, quiet=True)
    check(bool(adc.read_json(root / 'catalog.json')['damaged_files']), 'damaged report is preserved and identified without breaking preparation')

    code, _, console = launch('game', scene='', extra=['--quit-after', '20'])
    text = console.read_text(encoding='utf-8', errors='replace')
    check(code == 0 and 'SCRIPT ERROR' not in text and 'ERROR:' not in text, 'actual main scene loads, initializes player and exits without errors')
    failures = [entry['test'] for entry in checks if not entry['passed']]
    adc.atomic(output / 'validation.json', {'schema_version': 1, 'completed': adc.now(), 'engine': engine, 'checks': checks, 'passed': len(checks) - len(failures), 'failed': failures, 'native_crash_tested': False})
    print(f'ADC validation: {len(checks) - len(failures)}/{len(checks)} passed. Evidence: {output / "validation.json"}')
    return 1 if failures else 0
