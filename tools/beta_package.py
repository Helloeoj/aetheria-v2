"""Export a sanitized tester project; no source checkout or host credentials ship."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / 'godot_client'
RUNTIME_DIRS = {'Assets', 'autoload', 'data', 'diagnostics', 'network', 'scenes', 'scripts', 'shaders'}
EXTENSIONS = {'.gd', '.uid', '.tscn', '.tres', '.png', '.jpg', '.jpeg', '.webp', '.svg',
              '.ogg', '.wav', '.mp3', '.ttf', '.otf', '.gdshader', '.gdshaderinc', '.json', '.csv', '.import'}
SERVER_FILES = {'network/world_host.gd', 'network/authoritative_region.gd',
                'network/region_activities.gd', 'network/spatial_relevance.gd',
                'network/server_bootstrap.gd', 'scenes/network/WorldServer.tscn'}
PRESET = '''[preset.0]
name="Windows Beta Client"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features="tester_client"
export_filter="all_resources"
include_filter="*.json,*.csv,*.crt"
exclude_filter=""
export_path=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
binary_format/architecture="x86_64"
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
codesign/enable=false
application/modify_resources=false
'''


def excluded(path):
    text = path.as_posix()
    return (path.parts[0] not in RUNTIME_DIRS or any(part in {'dev_tools', 'server', 'tests', 'tools', '.godot'} for part in path.parts)
            or text.removesuffix('.uid') in SERVER_FILES or 'sentinel' in text.lower()
            or 'validation' in path.name.lower() or path.suffix.lower() not in EXTENSIONS)


def validate_profile(profile):
    from urllib.parse import urlsplit
    if not isinstance(profile, dict) or profile.get('schema') != 1:
        raise ValueError('Expected a public client profile schema 1.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', str(profile.get('release_id', ''))):
        raise ValueError('Invalid release identifier.')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', str(profile.get('world_id', ''))):
        raise ValueError('Invalid world identifier.')
    url = urlsplit(profile.get('account_url', ''))
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('Account endpoint must be an HTTPS URL without credentials.')
    if type(profile.get('world_port')) is not int or not 1 <= profile['world_port'] <= 65535:
        raise ValueError('Invalid world port.')
    for key in ('world_host', 'tls_name'):
        if not isinstance(profile.get(key), str) or not re.fullmatch(r'[A-Za-z0-9.:-]{1,253}', profile[key]):
            raise ValueError('Invalid public world hostname.')
    allowed = {'schema', 'release_id', 'world_id', 'account_url', 'world_host', 'world_port', 'tls_name', 'tls_certificate'}
    if set(profile) - allowed:
        raise ValueError('Unexpected client profile field; refusing possible private metadata.')


def stage(destination, profile, certificate):
    validate_profile(profile)
    if b'PRIVATE KEY' in certificate.read_bytes() or b'BEGIN CERTIFICATE' not in certificate.read_bytes():
        raise ValueError('Only a public X509 certificate may enter the tester project.')
    for path in SOURCE.rglob('*'):
        relative = path.relative_to(SOURCE)
        if not path.is_file() or excluded(relative):
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    project = (SOURCE / 'project.godot').read_text(encoding='utf-8')
    project = '\n'.join(line for line in project.splitlines() if not line.startswith('ServerBootstrap='))
    project = project.replace('config/name="Aetheria (Arcade Test Client)"', 'config/name="Aetheria Beta"')
    (destination / 'project.godot').write_text(project + '\n', encoding='utf-8')
    (destination / 'export_presets.cfg').write_text(PRESET, encoding='utf-8')
    profile = dict(profile, tls_certificate='res://data/beta_server.crt')
    (destination / 'data/beta_client.json').write_text(json.dumps(profile), encoding='utf-8')
    shutil.copyfile(certificate, destination / 'data/beta_server.crt')


def packed_files(executable):
    """Read Godot 4 PCK v2/v3 directory, including an embedded executable pack."""
    with executable.open('rb') as handle:
        def integer(fmt):
            size = struct.calcsize(fmt)
            raw = handle.read(size)
            if len(raw) != size:
                raise ValueError('Truncated package.')
            return struct.unpack(fmt, raw)[0]
        if handle.read(4) != b'GDPC':
            handle.seek(-12, 2)
            pack_size = integer('<Q')
            if handle.read(4) != b'GDPC':
                raise ValueError('Missing embedded package.')
            handle.seek(-12-pack_size, 2)
            if handle.read(4) != b'GDPC':
                raise ValueError('Invalid package header.')
        start = handle.tell() - 4
        version = integer('<I')
        handle.read(12)  # Engine version.
        flags, base = integer('<I'), integer('<Q')
        if version not in (2, 3) or flags & 1:
            raise ValueError('Unsupported package directory.')
        if version == 3:
            handle.seek(start + integer('<Q'))
        else:
            handle.read(64)
        count = integer('<I')
        if not 1 <= count <= 200000:
            raise ValueError('Invalid package directory size.')
        paths = []
        for _ in range(count):
            size = integer('<I')
            if size > 8192:
                raise ValueError('Invalid package path.')
            paths.append(handle.read(size).rstrip(b'\0').decode('utf-8'))
            handle.read(36)  # Offset, size, MD5, flags.
        return paths


def audit(executable):
    paths = packed_files(executable)
    for path in paths:
        relative = path.removeprefix('res://')
        lower = relative.lower()
        forbidden = (relative.endswith('.gd') or any('/'+part+'/' in '/'+lower+'/' for part in ['dev_tools', 'server', 'tools', 'tests', 'docs'])
                     or 'sentinel' in lower or lower.endswith(('.py', '.ps1', '.pem', '.key', '.pfx', '.p12'))
                     or any(relative.startswith(server.removesuffix('.gd')) for server in SERVER_FILES))
        if forbidden:
            raise ValueError('Forbidden tester resource: ' + relative)
    if not any(path.endswith('data/beta_client.json') for path in paths):
        raise ValueError('Tester profile is missing.')
    if not any(path.endswith('.gdc') for path in paths):
        raise ValueError('Compiled client scripts are missing.')
    return {'resources': len(paths), 'raw_scripts': 0, 'server_resources': 0}


def build(godot, profile, certificate, output):
    output = output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError('Choose a new empty output directory; releases are immutable.')
    output.mkdir(parents=True, exist_ok=True)
    evidence = output.parent / (output.name + '-validation')
    evidence.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='beta-stage-', dir=evidence) as temporary:
        staged = Path(temporary)
        stage(staged, profile, certificate)
        for name, args in [('import', ['--editor', '--import', '--quit']),
                           ('export', ['--export-release', 'Windows Beta Client', str(output / 'Aetheria.exe')])]:
            result = subprocess.run([str(godot), '--headless', '--path', str(staged), *args],
                                    capture_output=True, text=True, timeout=900,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            transcript = result.stdout + result.stderr
            (evidence / (name + '.log')).write_text(transcript, encoding='utf-8')
            if result.returncode or 'SCRIPT ERROR:' in transcript or 'ERROR:' in transcript:
                raise RuntimeError(f'Tester {name} failed; inspect external validation evidence: {evidence}')
        executable = output / 'Aetheria.exe'
        report = audit(executable)
        with executable.open('rb') as handle:
            checksum = hashlib.file_digest(handle, 'sha256').hexdigest()
        metadata = {'schema': 1, 'release_id': profile['release_id'], 'executable': 'Aetheria.exe',
                    'client_sha256': checksum, 'client_bytes': executable.stat().st_size}
        (output / 'release.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
        for notice in ('GODOT-LICENSE.txt', 'GODOT-COPYRIGHT.txt'):
            shutil.copyfile(REPO / 'licenses' / notice, output / notice)
        (evidence / 'audit.json').write_text(json.dumps(report), encoding='utf-8')
        # Boot the actual exported client, not its staged editor project.
        result = subprocess.run([str(executable), '--headless', '--quit-after', '8',
                                 '--log-file', str(evidence / 'boot.log'), '--', '--social-no-auto'],
                                capture_output=True, text=True, timeout=30)
        transcript = result.stdout + result.stderr
        (evidence / 'boot-console.log').write_text(transcript, encoding='utf-8')
        if result.returncode or 'SCRIPT ERROR:' in transcript or 'ERROR:' in transcript:
            raise RuntimeError(f'Exported tester startup failed; inspect {evidence}')
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--certificate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.godot, json.loads(args.profile.read_text(encoding='utf-8-sig')),
                           args.certificate, args.output)))


if __name__ == '__main__':
    main()
