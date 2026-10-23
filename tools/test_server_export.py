"""Verify an exported world on a separate loopback port; never restart the user's world."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time

from test_online import api, run_client


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-exe', required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--pack', help='Optional PCK for testing the export pack with an editor binary')
    args = parser.parse_args()
    installed = Path(os.environ['LOCALAPPDATA']) / 'Aetheria/online'
    output = Path(tempfile.mkdtemp(prefix='export-validation-', dir=installed))
    private = output / 'Aetheria/online'
    private.mkdir(parents=True)
    shutil.copyfile(installed / 'server.key', private / 'server.key')
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    world = 'export_' + secrets.token_hex(5)
    (private / 'world.json').write_text(json.dumps({'world_id': world, 'port': port, 'max_players': 2}))
    command = [args.server_exe, '--headless', '--log-file', str(output / 'world.log')]
    if args.pack:
        command += ['--main-pack', args.pack]
    # No --world-server flag: the dedicated export must select its own entry point.
    command += ['--', '--social-no-auto']
    with (output / 'world-console.log').open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, cwd=output, env=dict(os.environ,
            LOCALAPPDATA=str(output), AETHERIA_DIAGNOSTICS_DIR=str(output / 'adc')),
            stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        try:
            deadline = time.monotonic() + 90
            while not (private / 'world-ready.json').exists():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError(f'Export startup failed. Evidence: {output}')
                time.sleep(0.1)
            name = 'export_' + secrets.token_hex(5)
            password = secrets.token_urlsafe(24)
            registered = api('/api/register', {'username': name, 'password': password, 'password_confirmation': password})
            assert registered.get('ok'), 'Isolated account registration failed'
            first = run_client(args.godot, output / 'first', name, password, world_id=world, port=port)
            second = run_client(args.godot, output / 'second', name, password, expected=first['state'], world_id=world, port=port)
            assert first['character_id'] == second['character_id'], 'Export lost persistent identity'
        finally:
            if process.poll() is None:
                (private / 'world-stop.request').write_text('save-and-stop')
                process.wait(timeout=40)
    transcript = (output / 'world-console.log').read_text(encoding='utf-8')
    assert process.returncode == 0 and 'SCRIPT ERROR:' not in transcript and 'ERROR:' not in transcript, f'World runtime error. Evidence: {output}'
    print(f'[Server export] Startup, movement, save, reconnect and graceful shutdown passed. Evidence: {output}')


if __name__ == '__main__':
    main()
