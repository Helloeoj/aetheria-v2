"""Run real Smithing and crafting regressions; fail on script errors, retain external evidence."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import subprocess
import tempfile

import adc

CASES = {
    "smithing": ["res://scenes/dev_tools/smithing_smoke.tscn"],
    "smithing_ui": ["res://scenes/dev_tools/smithing_ui_smoke.tscn"],
    "crafting": ["--script", "res://scripts/dev_tools/crafting_service_smoke.gd"],
    "crafting_ui": ["res://scenes/dev_tools/crafting_ui_smoke.tscn"],
    "catalog": ["res://scenes/dev_tools/catalog_acquisition_smoke.tscn"],
}


def run_case(engine, output, name, render=False):
    folder = output / name
    folder.mkdir(parents=True, exist_ok=True)
    log = folder / "godot.log"
    command = [engine]
    if not render:
        command.append("--headless")
    command += ["--path", str(adc.GAME), "--log-file", str(log), *CASES[name]]
    if render:
        command += ["--", f"--capture={folder}"]
    env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(folder / "adc"),
               AETHERIA_NATIVE_LOG=str(log))
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=90, env=env)
        text = result.stdout + result.stderr
        summary = re.findall(r"\[[^\]\n]+\] (\d+) checks, (\d+) failures", text)
        if name == "catalog":
            summary = [(count, "0") for count in re.findall(r"\[Crafting acquisition\] PASS: (\d+) checks\.", text)]
        passed = (result.returncode == 0 and len(summary) == 1
                  and int(summary[0][0]) > 0 and int(summary[0][1]) == 0
                  and not re.search(r"SCRIPT ERROR:|ERROR:", text))
        exit_code = result.returncode
    except subprocess.TimeoutExpired as error:
        text, passed, exit_code = f"Timed out: {error}\n", False, None
    adc.atomic(folder / "validation.log", text)
    adc.atomic(folder / "validation.json", dict(passed=passed, exit_code=exit_code, command=command))
    return name, passed, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--render", action="store_true", help="Also capture the actual Smithing animation")
    args = parser.parse_args()
    output = (args.output or Path(tempfile.mkdtemp(prefix="aetheria-smithing-"))).resolve()
    if output.is_relative_to(adc.PROJECT.resolve()):
        parser.error("Evidence must be outside the repository")
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda name: run_case(args.godot, output, name), CASES))
    if args.render:
        results.append(run_case(args.godot, output / "rendered", "smithing_ui", True))
    for name, passed, text in results:
        print(f"{name}: {'PASS' if passed else 'FAIL'}")
        print(text if not passed else "\n".join(line for line in text.splitlines() if "checks," in line or "pacing]" in line))
    passed = all(result[1] for result in results)
    adc.atomic(output / "validation.json", dict(completed=adc.now(), passed=passed,
               cases=[dict(name=name, passed=ok) for name, ok, _ in results]))
    print(f"Validation evidence: {output}")
    return int(not passed)


if __name__ == "__main__":
    raise SystemExit(main())
