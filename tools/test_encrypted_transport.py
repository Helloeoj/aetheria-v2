"""Real encrypted ENet RPC round-trip and certificate rejection on isolated ports."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix='aetheria-dtls-'))

    def command(name, config):
        path = output / (name + '.json')
        path.write_text(json.dumps(config), encoding='utf-8')
        return [args.godot, '--headless', '--path', str(REPO / 'godot_client'),
                'res://scenes/dev_tools/encrypted_transport_smoke.tscn',
                '--log-file', str(output / (name + '.log')), '--', '--social-no-auto',
                '--test-input=' + str(path)]

    environment = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(output / 'adc'))
    certificates = {}
    for name in ('trusted', 'untrusted'):
        cert = {'key': str(output / (name + '.key')), 'certificate': str(output / (name + '.crt'))}
        certificates[name] = cert
        result = subprocess.run(command(name, dict(cert, mode='certificate')), env=environment,
                                capture_output=True, text=True, timeout=20)
        assert result.returncode == 0 and 'SCRIPT ERROR' not in result.stdout + result.stderr, result.stdout + result.stderr
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    ready, stop = output / 'ready', output / 'stop'
    with (output / 'server-console.log').open('w') as log:
        server = subprocess.Popen(command('server', dict(certificates['trusted'], mode='server',
            port=port, ready=str(ready), stop=str(stop))), env=environment,
            stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        try:
            deadline = time.monotonic() + 20
            while not ready.exists():
                assert server.poll() is None and time.monotonic() < deadline, f'Server failed: {output}'
                time.sleep(.1)
            for name, cert, tls_name, expected in [
                ('valid', 'trusted', 'aetheria-beta', True),
                ('wrong-certificate', 'untrusted', 'aetheria-beta', False),
                ('wrong-name', 'trusted', 'other-world', False),
            ]:
                config = dict(mode='client', port=port, certificate=certificates[cert]['certificate'],
                              tls_name=tls_name, expected=expected, output=str(output / (name + '-result.json')))
                result = subprocess.run(command(name, config), env=environment,
                                        capture_output=True, text=True, timeout=25)
                (output / (name + '-console.log')).write_text(result.stdout + result.stderr)
                assert result.returncode == 0, f'{name} failed: {output}\n{result.stdout}{result.stderr}'
                assert json.loads(Path(config['output']).read_text())['connected'] == expected
        finally:
            stop.write_text('stop')
            server.wait(timeout=10)
    assert server.returncode == 0
    print('[Encrypted transport] Valid RPC round trip, untrusted certificate and wrong name rejection passed.')
    print('Evidence:', output)


if __name__ == '__main__':
    main()
