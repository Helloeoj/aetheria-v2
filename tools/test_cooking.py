"""Run real Godot cooking and adjacent fishing/food regressions; retain logs outside the repo."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import subprocess
import tempfile

import adc


SCENES = (
    'cooking_smoke', 'cooking_ui_smoke', 'tavern_integration', 'fish_food_smoke', 'fishing_pale_smoke',
    'food_input_smoke', 'fish_inventory_slots_smoke', 'fishing_smoke',
    'fishing_cast_pacing_smoke', 'fishing_input_smoke', 'skill_tools_smoke',
    'fishing_difficulty_smoke',
)


def run_scene(engine, output, scene):
    folder = output / scene
    folder.mkdir(parents=True, exist_ok=True)
    log = folder / 'godot.log'
    command = [engine, '--headless', '--path', str(adc.GAME), '--log-file', str(log),
               f'res://scenes/dev_tools/{scene}.tscn']
    env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(folder / 'adc'),
               AETHERIA_NATIVE_LOG=str(log))
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=90, env=env)
        text = result.stdout + result.stderr
        summaries = re.findall(r'\[[^\]\n]+\] (\d+) checks, (\d+) failures', text)
        passed = (result.returncode == 0 and len(summaries) == 1
                  and int(summaries[0][1]) == 0 and int(summaries[0][0]) > 0
                  and 'SCRIPT ERROR:' not in text and 'ERROR:' not in text)
        exit_code = result.returncode
    except subprocess.TimeoutExpired as error:
        text = f'Timed out: {error}\n'
        summaries = []
        passed = False
        exit_code = None
    adc.atomic(folder / 'validation.log', text)
    adc.atomic(folder / 'validation.json', dict(completed=adc.now(), passed=passed,
               exit_code=exit_code, command=command))
    return scene, passed, summaries, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--scene', action='append', choices=SCENES)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix='aetheria-cooking-'))
    output = output.resolve()
    if output.is_relative_to(adc.PROJECT.resolve()):
        parser.error('--output must be outside the repository')
    scenes = args.scene or SCENES
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda scene: run_scene(args.godot, output, scene), scenes))
    passed = True
    for scene, success, summaries, text in results:
        passed = passed and success
        print(f'{scene}: {"PASS" if success else "FAIL"} {summaries}')
        if not success:
            print(text)
    adc.atomic(output / 'validation.json', dict(completed=adc.now(), passed=passed,
               scenes=[dict(scene=s, passed=p, counts=c) for s, p, c, _ in results]))
    print(f'Validation evidence: {output}')
    return int(not passed)


if __name__ == '__main__':
    raise SystemExit(main())
