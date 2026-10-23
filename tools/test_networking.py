"""Run isolated Godot networking regressions with evidence outside the repository."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
SCENES = [
    'character_persistence_smoke', 'region_authority_smoke',
    'online_activity_smoke', 'snapshot_transport_smoke',
    'world_host_persistence_smoke', 'region_freeze_smoke',
    'online_region_travel_smoke',
    'development_controls_smoke',
    'original_online_minigames_smoke',
    'fishing_responsiveness_smoke',
    'cooking_responsiveness_smoke',
]
SCRIPTS = ['online_activity_input_smoke', 'developer_sandbox_smoke']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix='aetheria-network-tests-'))
    output.mkdir(parents=True, exist_ok=True)
    for name in SCENES + SCRIPTS:
        evidence = output / name
        evidence.mkdir(exist_ok=True)
        environment = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(evidence / 'adc'),
                           AETHERIA_NATIVE_LOG=str(evidence / 'godot.log'))
        target = (['--script', f'res://scripts/dev_tools/{name}.gd'] if name in SCRIPTS
                  else [f'res://scenes/dev_tools/{name}.tscn'])
        command = [args.godot, '--headless', '--path', str(REPO / 'godot_client'),
                   *target, '--log-file',
                   str(evidence / 'godot.log'), '--', '--social-no-auto']
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=100, env=environment)
        transcript = result.stdout + result.stderr
        (evidence / 'validation.log').write_text(transcript, encoding='utf-8')
        print(transcript, end='')
        assert result.returncode == 0, f'{name}: process failed; see {evidence}'
        assert 'SCRIPT ERROR:' not in transcript and 'ERROR:' not in transcript, (
            f'{name}: runtime error; see {evidence}')
        assert re.search(r'0 failures|PASS:', transcript), f'{name}: missing pass marker'
    print(f'[Networking suite] {len(SCENES) + len(SCRIPTS)} tests passed. Evidence: {output}')


if __name__ == '__main__':
    main()
