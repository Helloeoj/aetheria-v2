"""Isolated model, real-process and Tk interaction regression tests for Sentinel."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import tkinter as tk
import adc
from sentinel import SentinelApp
from sentinel_monitor import Monitor, LogTail
from sentinel_windows import ProcessWatch, godot_pids, is_game, engine_processes, game_executable, HIDDEN


def run(engine, output):
    engine = game_executable(engine)
    output.mkdir(parents=True, exist_ok=True)
    checks = []

    def check(value, name):
        checks.append({'test': name, 'passed': bool(value)})
        print(('PASS ' if value else 'FAIL ') + name, flush=True)

    def wait(model, condition, seconds=25):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            model.step()
            if condition():
                return True
            time.sleep(.15)
        return False

    tail = LogTail()
    log = output / 'tail.log'
    log.write_bytes(b'first\npart')
    check(tail.read(log) == ['first'], 'native tail waits for complete lines')
    with log.open('ab') as stream:
        stream.write(b'ial\n')
    check(tail.read(log) == ['partial'] and tail.read(log) == [], 'incremental append is read once with partial-line reassembly')
    log.write_text('new\n', encoding='utf-8')
    check(tail.read(log) == ['new'], 'log truncation resets its cursor')
    log.write_text('x' * 200000 + '\n', encoding='utf-8')
    fresh = tail.read(log)
    check(len(tail.lines) <= 400 and any('budget' in line for line in fresh), 'live log burst is bounded and explicitly labelled')
    command = subprocess.list2cmdline([engine, '--path', str(adc.GAME)])
    check(is_game(command, adc.GAME) and not is_game(command + ' --editor', adc.GAME), 'only the matching game project is classified as a game, not its editor')

    root = output / 'normal'
    model = Monitor(root, discover=False)
    model.engine = engine
    pid = model.launch(extra=['--headless', 'res://diagnostics/probe.tscn'])
    check(wait(model, lambda: not model.active), 'launched test game exit is observed')
    check(model.last_exit and model.last_exit['clean'] and model.last_exit['code'] == 0, 'normal exit retains original process exit code and clean marker')
    check(any('started' in e['message'] for e in model.activity), 'game launch is represented in independent activity history')
    check(any('ADC single synthetic' in row['data']['message'] for row in model.records.values()), 'persisted ADC incidents appear in companion model')

    root = output / 'abnormal'
    model = Monitor(root, discover=False)
    model.engine = engine
    pid = model.launch(extra=['--headless', 'res://diagnostics/probe.tscn', '--', '--probe=hold'])
    child = model.active[pid]['child']
    try:
        ready = wait(model, lambda: bool(model.active.get(pid, {}).get('session')) and any('ADC PROBE READY' in line for line in model.tail.lines))
        check(ready, 'live test-game session, native errors and readiness are observed while game is alive')
        child.kill()  # This is the isolated process launched immediately above; never a user's game/editor.
        child.wait(timeout=10)
        exited = wait(model, lambda: not model.active)
        check(exited and model.last_exit and not model.last_exit['clean'], 'abrupt test termination is distinguished from normal shutdown')
        check(any(r['data'].get('kind') == 'suspected_termination' for r in model.records.values()), 'independent companion prepares a recovery report without restarting Godot')
        model.step()
        check((root / 'companion/last-log-tail.txt').is_file() and not model.stop_event.is_set(), 'companion stays operational and preserves the last native tail after game termination')
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        model.close()

    # UI construction/actions use the app's own methods, not generic OS/UI automation.
    window = tk.Tk()
    ui_model = Monitor(output / 'ui', discover=False)
    app = SentinelApp(window, ui_model, start=False)
    try:
        app.apply(model.snapshot())
        window.update()
        check(window.winfo_width() >= 920 and app.incident_card.cget('text') != '0', 'real Tk window renders live model state and incident count')
        app.tabs.select(1)
        app.select_incident()
        window.update()
        check(bool(app.selected) and len(app.detail.get('1.0', 'end').strip()) > 40
              and 'AETHERIA DIAGNOSTIC REPORT' not in app.detail.get('1.0', 'end'), 'incident selection leads with a human explanation')
        app.copy_selected()
        check('AETHERIA DIAGNOSTIC REPORT' in window.clipboard_get(), 'copy-selected action produces a usable Codex report')
        app.filter.set('All retained')
        app._show_incidents(force=True)
        check(bool(app.incidents.get_children()), 'incident history filter is interactive')
        app.background()
        window.update()
        check(window.state() == 'iconic' and not ui_model.stop_event.is_set(), 'background button minimizes without stopping monitoring')
        window.deiconify()
        window.update()
    finally:
        app.close()

    # App shutdown is independent of the game process.
    live_model = Monitor(output / 'close_companion', discover=False)
    live_model.engine = engine
    pid = live_model.launch(extra=['--headless', 'res://diagnostics/probe.tscn', '--', '--probe=hold'])
    game = live_model.active[pid]['child']
    try:
        check(wait(live_model, lambda: any('ADC PROBE READY' in line for line in live_model.tail.lines)), 'separate game is ready for companion-close test')
        live_model.close()
        time.sleep(.2)
        check(game.poll() is None, 'closing companion does not close or terminate the game')
    finally:
        game.kill()
        game.wait(timeout=10)
        for record in live_model.active.values():
            record['watch'].close()

    # Real separate GUI process survives an externally launched game stopping.
    independent_root = output / 'independent_gui'
    companion = subprocess.Popen([sys.executable, str(adc.PROJECT / 'tools/sentinel.py'), '--root', str(independent_root), '--background'],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=HIDDEN)
    native = output / 'independent-game.log'
    env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(independent_root), AETHERIA_NATIVE_LOG=str(native))
    game = subprocess.Popen([engine, '--headless', '--path', str(adc.GAME), '--log-file', str(native), 'res://diagnostics/probe.tscn', '--', '--probe=hold'],
                            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=HIDDEN)
    try:
        deadline = time.monotonic() + 30
        seen = False
        while time.monotonic() < deadline and companion.poll() is None:
            activity = adc.read_json(independent_root / 'companion/activity.json', [])
            if any(f'PID {game.pid}' in e.get('message', '') and 'started' in e['message'] for e in activity):
                seen = True
                break
            time.sleep(.2)
        check(seen, 'actual standalone GUI detects a game launched outside the companion')
        game.kill()
        game.wait(timeout=10)
        deadline = time.monotonic() + 20
        def observed_test_exit():
            receipt = adc.read_json(independent_root / 'companion/last-exit.json', {})
            if receipt.get('pid') == game.pid and not receipt.get('clean'):
                return True
            # Other project chats can launch/close Godot concurrently. Their
            # later receipt may replace last-exit; retained activity still proves
            # this exact owned test process was observed stopping unexpectedly.
            return any(f'Unexpected stop — PID {game.pid},' in row.get('message', '')
                       for row in adc.read_json(independent_root / 'companion/activity.json', []))
        while time.monotonic() < deadline and not observed_test_exit() and companion.poll() is None:
            time.sleep(.2)
        check(companion.poll() is None and observed_test_exit(), 'standalone GUI remains running after observed test-game termination')
    finally:
        if game.poll() is None:
            game.kill()
            game.wait()
        companion.terminate()  # Only the isolated test app, not the user's installed companion.
        companion.wait(timeout=10)

    failures = [c['test'] for c in checks if not c['passed']]
    adc.atomic(output / 'validation.json', {'completed': adc.now(), 'passed': len(checks) - len(failures), 'failed': failures, 'checks': checks})
    print(f'Sentinel: {len(checks) - len(failures)}/{len(checks)} passed. Evidence: {output / "validation.json"}')
    return 1 if failures else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, default=None)
    args = parser.parse_args()
    raise SystemExit(run(args.godot, args.output or Path(tempfile.mkdtemp(prefix='aetheria-sentinel-tests-'))))
