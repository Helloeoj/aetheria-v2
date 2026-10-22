"""Run focused movement regressions; keep diagnostics outside the checkout."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix='aetheria-movement-'))
    for name, script in [('movement_presentation_smoke', True),
                         ('movement_server_smoke', False),
                         ('online_movement_smoke', True)]:
        evidence = output / name
        evidence.mkdir()
        target = (['--script', f'res://scripts/dev_tools/{name}.gd'] if script
                  else [f'res://scenes/dev_tools/{name}.tscn'])
        result = subprocess.run(
            [args.godot, '--headless', '--path', str(REPO / 'godot_client'),
             *target, '--log-file', str(evidence / 'godot.log'), '--', '--social-no-auto'],
            env=dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(evidence / 'adc')),
            capture_output=True, text=True, timeout=90)
        transcript = result.stdout + result.stderr
        (evidence / 'validation.log').write_text(transcript, encoding='utf-8')
        print(transcript, end='')
        assert result.returncode == 0 and '0 failures' in transcript, name
        assert 'SCRIPT ERROR:' not in transcript and 'ERROR:' not in transcript, name
    print(f'[Movement suite] 3 tests passed. Evidence: {output}')


if __name__ == '__main__':
    main()
