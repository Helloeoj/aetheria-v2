"""Build an immutable tester release, publish a capped patch, then activate it."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

import beta_ops
import beta_package
import server_ops

REPO, DATA, HIDDEN = beta_ops.REPO, beta_ops.DATA, beta_ops.HIDDEN


def upload_ready(state, upload, release):
    return any(channel.get('name') == 'windows-beta' and channel.get('uploadId') == upload
               and channel.get('head', {}).get('state') == 'completed'
               and channel.get('head', {}).get('userVersion') == release
               for channel in state.get('channels', []))


def run(command, log=None, timeout=120):
    if log:
        with log.open('w', encoding='utf-8') as output:
            subprocess.run([str(part) for part in command], cwd=REPO, stdout=output,
                stderr=subprocess.STDOUT, check=True, timeout=timeout, creationflags=HIDDEN)
    else:
        subprocess.run([str(part) for part in command], cwd=REPO, check=True,
            timeout=timeout, creationflags=HIDDEN)


def publish(settings, output, release):
    runtime = DATA / 'beta-runtime'
    butler = runtime / 'butler/butler.exe'
    identity = runtime / 'itch-publisher-creds'
    run([sys.executable, REPO / 'tools/capped_transfer.py', '--', butler,
         '--address', 'https://api.itch.io', 'push', output,
         'helloeoj/aetheria-beta:windows-beta', '--identity', identity,
         '--userversion', release], runtime / 'release-upload.log', timeout=3600)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        result = subprocess.run([str(butler), '--address', 'https://api.itch.io', '--json',
            'status', 'helloeoj/aetheria-beta:windows-beta', '--identity', str(identity)],
            capture_output=True, text=True, timeout=25, creationflags=HIDDEN)
        if result.returncode:
            raise RuntimeError('The upload status could not be verified; release was not activated.')
        for line in result.stdout.splitlines():
            try:
                item = json.loads(line)
            except ValueError:
                continue
            if item.get('type') == 'result' and upload_ready(item['value'], settings['upload_id'], release):
                print('Exact private game upload finished processing.')
                return
        time.sleep(5)
    raise RuntimeError('The upload is still processing; release was not activated.')


def validate_metadata(metadata, release):
    if (not isinstance(metadata, dict) or metadata.get('schema') != 1
            or metadata.get('release_id') != release or metadata.get('executable') != 'Aetheria.exe'
            or not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', str(release))
            or not re.fullmatch(r'[a-f0-9]{64}', str(metadata.get('client_sha256', '')))
            or type(metadata.get('client_bytes')) is not int or metadata['client_bytes'] <= 0):
        raise ValueError('Invalid or mismatched client release metadata.')


def verify_client(output, release):
    metadata = beta_ops.read_json(output / 'release.json')
    validate_metadata(metadata, release)
    exe = output / metadata['executable']
    if exe.stat().st_size != metadata['client_bytes'] or server_ops.sha256(exe) != metadata['client_sha256']:
        raise RuntimeError('The existing tester executable failed release integrity verification.')
    return metadata


def seal_pair(output, metadata, candidate):
    """The private receipt binds future reuse to this exact validated pair."""
    receipt = output.parent / (output.name + '-validation') / 'release-candidate.json'
    value = {'schema': 1, 'client': metadata, 'server_candidate': str(Path(candidate).resolve())}
    if receipt.exists():
        if beta_ops.read_json(receipt) != value:
            raise RuntimeError('The immutable release pair does not match this candidate.')
    else:
        with receipt.open('x', encoding='utf-8') as handle:
            json.dump(value, handle, indent=2)


def reuse_release(output, release, server_manifest):
    """Explicit reuse attests that legacy artifacts were validated together."""
    metadata = verify_client(output, release)
    exe = output / metadata['executable']
    evidence = output.parent / (output.name + '-validation')
    if beta_ops.read_json(evidence / 'audit.json') != beta_package.audit(exe):
        raise RuntimeError('The tester resource audit does not match the validated release.')
    for name in ('import.log', 'export.log', 'boot.log', 'boot-console.log'):
        if 'ERROR:' in (evidence / name).read_text(encoding='utf-8-sig'):
            raise RuntimeError('Existing tester validation failed; rebuild with a new release ID.')
    # Old logs are written even when the exported process fails without an
    # error message. Boot the exact verified executable before sealing reuse.
    result = subprocess.run([str(exe), '--headless', '--quit-after', '8',
        '--log-file', str(evidence / 'reuse-boot.log'), '--', '--social-no-auto'],
        capture_output=True, text=True, timeout=30, creationflags=HIDDEN)
    transcript = result.stdout + result.stderr
    (evidence / 'reuse-boot-console.log').write_text(transcript, encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR:' in transcript or 'ERROR:' in transcript:
        raise RuntimeError('Existing tester boot failed; release reuse was rejected.')
    if verify_client(output, release) != metadata:
        raise RuntimeError('The tester release changed during the reuse boot check.')
    selected = beta_ops.read_json(server_manifest)
    if selected.get('schema') == 2:
        candidate = Path(selected['exe']).resolve().parent / 'server-candidate.json'
        if server_ops.verify_candidate(candidate, release) != selected:
            raise RuntimeError('The supplied server selection differs from its immutable candidate.')
    elif selected.get('schema') == 1 and selected.get('repo') == str(REPO):
        # Migration for exports made before candidate manifests existed. This
        # requires the operator's explicit matching-pair attestation; filenames
        # and timestamps cannot prove that historical builds were paired.
        server = Path(selected['exe']).resolve()
        if server.parent.parent != (DATA / 'server-builds').resolve():
            raise RuntimeError('Only an installed dedicated server export may be enrolled.')
        if 'ERROR:' in (server.parent / 'export.log').read_text(encoding='utf-8-sig'):
            raise RuntimeError('The existing dedicated server export failed validation.')
        runtime_path = DATA / 'server-runtime.json'
        if runtime_path.exists():
            runtime = beta_ops.read_json(runtime_path)
            if (runtime.get('schema') != 1 or runtime.get('version') != '4.7.2'
                    or server_ops.sha256(Path(runtime['exe'])) != runtime.get('sha256')
                    or server_ops.sha256(server) != runtime.get('sha256')):
                raise RuntimeError('The existing dedicated server failed pinned runtime verification.')
        candidate = server_ops.candidate_manifest(server, release)
    else:
        raise RuntimeError('The existing server manifest is not eligible for release reuse.')
    seal_pair(output, metadata, candidate)
    return metadata, candidate


def activate(settings, metadata, candidate_path):
    if (DATA / 'beta-runtime/activation.pending').exists():
        raise RuntimeError('An interrupted beta release activation requires recovery before retrying.')
    validate_metadata(metadata, metadata.get('release_id'))
    candidate = server_ops.verify_candidate(candidate_path, metadata['release_id'])
    output = DATA / 'beta-builds' / metadata['release_id']
    receipt = output.parent / (output.name + '-validation') / 'release-candidate.json'
    if (verify_client(output, metadata['release_id']) != metadata
            or beta_ops.read_json(receipt) != {'schema': 1, 'client': metadata,
                'server_candidate': str(Path(candidate_path).resolve())}):
        raise RuntimeError('Activation requires the exact validated client/server pair.')
    # Save first. The account process remains available until every world save
    # and release is confirmed; failed saves never trigger a forced world kill.
    beta_ops.stop()
    print('Creating a private recovery bundle.')
    server_ops.backup()
    run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
         REPO / 'tools/accounts.ps1', 'stop'])
    # Account startup applies the additive migration before any public ingress.
    run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
         REPO / 'tools/accounts.ps1', 'start'])
    run([sys.executable, '-m', 'backend.beta_admin', 'grant', settings['owner_username']])
    # A crash between the three pointer replacements must never restart a
    # partially selected release. Keep this marker until all agree and verify.
    activation = DATA / 'beta-runtime/activation.pending'
    with activation.open('x', encoding='utf-8') as handle:
        json.dump({'release_id': metadata['release_id'], 'candidate': str(candidate_path)}, handle)
    world_path = DATA / 'world.json'
    world = beta_ops.read_json(world_path) if world_path.exists() else {}
    world.update({'world_id': settings['world_id'], 'port': 24567, 'release_id': metadata['release_id'],
        'bind_address': '127.0.0.1', 'account_url': 'http://127.0.0.1:8780',
        'tls_key': str(DATA / 'beta-runtime/world-private.key'),
        'tls_certificate': str(DATA / 'beta-runtime/world-public.crt')})
    beta_ops.write_json(world_path, world)
    policy = beta_ops.public_profile(settings, metadata['release_id'])
    policy.pop('tls_name')
    policy.update({'enabled': True, 'client_sha256': metadata['client_sha256'],
                   'client_bytes': metadata['client_bytes']})
    beta_ops.write_json(DATA / 'beta.json', policy)
    beta_ops.write_json(DATA / 'server-build.json', candidate)
    server_ops.verify_selection(DATA)
    activation.unlink()
    beta_ops.start(settings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--reuse-server-build', type=Path,
        help='Reuse the existing validated client and matching server manifest; attests legacy builds were paired.')
    parser.add_argument('--release', default='beta-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    parser.add_argument('--publish', action='store_true', help='Upload the private build after local validation.')
    parser.add_argument('--activate', action='store_true', help='Save/restart the matching world after verified publication.')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', args.release):
        parser.error('Invalid release identifier.')
    if args.activate and not args.publish:
        parser.error('Activation requires verified publication.')
    if not args.godot and not args.reuse_server_build:
        parser.error('--godot is required unless reusing an existing validated release.')
    settings = beta_ops.read_json(DATA / 'beta-runtime/hosting.json')
    output = DATA / 'beta-builds' / args.release
    # An explicit lock avoids two owners publishing/activating conflicting releases.
    lock = DATA / 'beta-runtime/release.lock'
    try:
        with lock.open('x', encoding='utf-8') as handle:
            json.dump(beta_ops.process_identity(os.getpid()), handle)
    except FileExistsError:
        raise RuntimeError('Another release is running or needs recovery. Inspect private release.lock before retrying.')
    try:
        if args.reuse_server_build:
            metadata, candidate = reuse_release(output, args.release, args.reuse_server_build)
            print('Existing validated client/server pair verified without export.', flush=True)
        else:
            print('Building and auditing tester client ' + args.release, flush=True)
            metadata = beta_package.build(args.godot, beta_ops.public_profile(settings, args.release),
                DATA / 'beta-runtime/world-public.crt', output)
            print('Tester client boot and source/server resource audit passed.', flush=True)
            validate_metadata(metadata, args.release)
            candidate = server_ops.build(args.godot, release_id=args.release)
            seal_pair(output, metadata, candidate)
            print('Matching dedicated server built.', flush=True)
        if args.publish:
            publish(settings, output, args.release)
        if args.activate:
            activate(settings, metadata, candidate)
        print('Release output: ' + str(output))
    finally:
        lock.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
