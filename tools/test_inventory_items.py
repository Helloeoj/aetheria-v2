"""Real Godot pickup/UI regression; script errors fail even if Godot exits zero."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import adc


def run(engine, output):
    output.mkdir(parents=True, exist_ok=True)
    log = output / 'godot.log'
    command = [engine, '--headless', '--path', str(adc.GAME), '--log-file', str(log),
               '--script', 'res://scripts/dev_tools/inventory_items_smoke.gd']
    result = subprocess.run(command, capture_output=True, text=True, timeout=45,
                            env=dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(output / 'adc'), AETHERIA_NATIVE_LOG=str(log)))
    text = result.stdout + result.stderr
    adc.atomic(output / 'validation.log', text)
    passed = result.returncode == 0 and bool(re.search(r'\[Inventory items\] \d+ checks, 0 failures', text)) and 'SCRIPT ERROR:' not in text and 'ERROR:' not in text
    adc.atomic(output / 'validation.json', {'completed': adc.now(), 'passed': passed, 'exit_code': result.returncode, 'command': command})
    print(text)
    return int(not passed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    raise SystemExit(run(args.godot, args.output or Path(tempfile.mkdtemp(prefix='aetheria-inventory-'))))
