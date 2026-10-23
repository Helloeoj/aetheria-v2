"""Private PC beta orchestration. Public ingress never exposes the account host API."""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request

import server_ops

REPO = Path(__file__).resolve().parents[1]
DATA = Path(os.environ['LOCALAPPDATA']) / 'Aetheria/online'
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
SERVICES = ('gateway', 'tunnel', 'relay')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_json(path, value):
    pending = path.with_suffix('.pending')
    pending.write_text(json.dumps(value, indent=2), encoding='utf-8')
    pending.replace(path)


def process_identity(pid):
    """PID alone is unsafe after restarts; bind it to image and creation FILETIME."""
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.restype = wintypes.HANDLE
    handle = kernel.OpenProcess(0x1000, False, int(pid))
    if not handle:
        return None
    try:
        size = wintypes.DWORD(32768)
        name = ctypes.create_unicode_buffer(size.value)
        created, exited, system, user = (wintypes.FILETIME() for _ in range(4))
        if not kernel.QueryFullProcessImageNameW(wintypes.HANDLE(handle), 0, name, ctypes.byref(size)):
            return None
        if not kernel.GetProcessTimes(wintypes.HANDLE(handle), ctypes.byref(created),
                ctypes.byref(exited), ctypes.byref(system), ctypes.byref(user)):
            return None
        return {'pid': int(pid), 'exe': str(Path(name.value).resolve()),
                'created': created.dwLowDateTime + (created.dwHighDateTime << 32)}
    finally:
        kernel.CloseHandle(wintypes.HANDLE(handle))


def matches(record):
    if not isinstance(record, dict):
        return False
    try:
        current = process_identity(record['pid'])
        return (current is not None and current['created'] == record['created']
                and os.path.normcase(current['exe']) == os.path.normcase(record['exe']))
    except (KeyError, TypeError, ValueError, OSError):
        return False


def stop_owned(record):
    if not matches(record):
        return
    # These helpers have no gameplay state. The world is stopped separately,
    # through its save-and-release request, and is never terminated here.
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.restype = wintypes.HANDLE
    handle = kernel.OpenProcess(0x1001, False, record['pid'])
    if not handle:
        return
    try:
        created, exited, system, user = (wintypes.FILETIME() for _ in range(4))
        if kernel.GetProcessTimes(wintypes.HANDLE(handle), ctypes.byref(created), ctypes.byref(exited),
                ctypes.byref(system), ctypes.byref(user)):
            stamp = created.dwLowDateTime + (created.dwHighDateTime << 32)
            if stamp == record['created']:
                kernel.TerminateProcess(wintypes.HANDLE(handle), 0)
    finally:
        kernel.CloseHandle(wintypes.HANDLE(handle))


def quick_origin(text):
    match = re.search(r'https://[a-z0-9]+(?:-[a-z0-9]+)*\.trycloudflare\.com(?=[\s"|\\]|$)', text)
    return match.group(0) if match else None


def public_profile(settings, release):
    return {'schema': 1, 'release_id': release, 'world_id': settings['world_id'],
            'account_url': settings['account_url'], 'world_host': settings['world_host'],
            'world_port': settings['world_port'], 'tls_name': 'aetheria-beta'}


def online(action):
    subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', str(REPO / 'tools/online.ps1'), action], cwd=REPO, check=True, creationflags=HIDDEN)


def spawn(name, args, records):
    runtime = DATA / 'beta-runtime'
    with (runtime / (name + '-stdout.log')).open('w', encoding='utf-8') as out, \
            (runtime / (name + '-stderr.log')).open('w', encoding='utf-8') as err:
        child = subprocess.Popen([str(arg) for arg in args], cwd=REPO, stdout=out, stderr=err,
            stdin=subprocess.DEVNULL, creationflags=HIDDEN | subprocess.DETACHED_PROCESS)
    identity = process_identity(child.pid)
    if identity is None:
        raise RuntimeError(name + ' exited before startup.')
    records[name] = identity
    write_json(DATA / 'beta-processes.json', records)
    return child


def deploy_origin(settings, origin):
    environment = dict(os.environ, WRANGLER_SEND_METRICS='false')
    environment['PATH'] = str(Path(settings['node']).parent) + os.pathsep + environment['PATH']
    command = [settings['node'], settings['wrangler'], 'deploy', '--config', settings['worker_config'],
               '--keep-vars', '--var', 'ORIGIN_URL:' + origin]
    with (DATA / 'beta-runtime/edge-deploy.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=REPO, env=environment, stdout=log,
            stderr=subprocess.STDOUT, creationflags=HIDDEN, timeout=120)
    if result.returncode:
        raise RuntimeError('HTTPS address refresh failed. Inspect the private edge-deploy.log.')


def _start(settings):
    server_ops.validate_startup(DATA)
    policy = read_json(DATA / 'beta.json')
    if policy.get('enabled') is not True:
        raise RuntimeError('A validated beta release must be enabled before public hosting.')
    records_path = DATA / 'beta-processes.json'
    records = read_json(records_path) if records_path.exists() else {}
    if all(matches(records.get(name)) for name in SERVICES):
        status(settings)
        return
    # A partial ingress stack must be rebuilt together, so the Worker points at
    # the current tunnel. Do not interrupt a healthy world or account service.
    for name in reversed(SERVICES):
        stop_owned(records.get(name))
    records = {}
    online('start')
    ingress = read_json(DATA / 'ingress.json')
    gateway = spawn('gateway', [sys.executable, '-m', 'backend.public_gateway'], records)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if gateway.poll() is not None:
            raise RuntimeError('The private player gateway did not start.')
        try:
            request = urllib.request.Request(f"http://127.0.0.1:{ingress['port']}/health", headers={
                'X-Aetheria-Ingress': ingress['token'], 'X-Aetheria-Client-IP': '127.0.0.1'})
            with urllib.request.urlopen(request, timeout=1) as response:
                if json.load(response).get('ok'):
                    break
        except OSError:
            time.sleep(.2)
    else:
        raise RuntimeError('The private player gateway readiness check timed out.')
    tunnel = spawn('tunnel', [settings['cloudflared'], 'tunnel', '--no-autoupdate', '--url',
        f"http://127.0.0.1:{ingress['port']}", '--protocol', 'http2'], records)
    origin = None
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if tunnel.poll() is not None:
            raise RuntimeError('The HTTPS tunnel exited during startup.')
        log = (DATA / 'beta-runtime/tunnel-stderr.log').read_text(encoding='utf-8', errors='replace')
        origin = quick_origin(log)
        if origin:
            break
        time.sleep(.25)
    if origin is None:
        raise RuntimeError('The HTTPS tunnel did not allocate an address.')
    deploy_origin(settings, origin)
    spawn('relay', [settings['playit'], '--secret_path', settings['playit_secret'], '--stdout', 'start'], records)
    write_json(DATA / 'beta-active.json', {'origin': origin, 'account_url': settings['account_url'],
                                        'release_id': policy['release_id']})
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(settings['account_url'] + '/api/release', timeout=5) as response:
                public = json.load(response)
            if public.get('release_id') == policy['release_id'] and public.get('enabled') is True:
                print('Beta login/version service ready at ' + settings['account_url'])
                print(f"Encrypted game relay: {settings['world_host']}:{settings['world_port']}")
                return
        except OSError:
            pass
        time.sleep(.5)
    raise RuntimeError('Public version check is not ready. No successful hosting claim was made.')


def stop():
    # Stop accepting new connections first, then let the world finalize saves.
    path = DATA / 'beta-processes.json'
    records = read_json(path) if path.exists() else {}
    for name in reversed(SERVICES):
        stop_owned(records.get(name))
    path.unlink(missing_ok=True)
    online('stop')
    print('Public ingress stopped; the world saved and stopped. Account storage remains running.')


def clean_failed_ingress():
    path = DATA / 'beta-processes.json'
    if path.exists():
        records = read_json(path)
        for name in reversed(SERVICES):
            stop_owned(records.get(name))
        path.unlink(missing_ok=True)


def start(settings):
    try:
        _start(settings)
    except Exception:
        clean_failed_ingress()
        raise


def status(settings):
    path = DATA / 'beta-processes.json'
    records = read_json(path) if path.exists() else {}
    for name in SERVICES:
        print(name + ': ' + ('running' if matches(records.get(name)) else 'stopped'))
    online('status')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['start', 'stop', 'status', 'profile'])
    parser.add_argument('--release')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    settings = read_json(DATA / 'beta-runtime/hosting.json')
    if args.action == 'profile':
        if not args.release or not args.output:
            parser.error('profile requires --release and --output')
        write_json(args.output, public_profile(settings, args.release))
    elif args.action == 'start':
        start(settings)
    elif args.action == 'stop':
        stop()
    else:
        status(settings)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
