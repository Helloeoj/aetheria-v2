"""Run real Starforged/crafting regressions with isolated logs outside the repo."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import subprocess
import tempfile

import adc


SCENES = (
    "starforged_acquisition_smoke", "catalog_acquisition_smoke",
    "smithing_catalog_smoke", "bronze_recipes_smoke", "crafting_ui_smoke",
    "runite_equipment_smoke", "character_persistence_smoke",
    "mining_definitions_smoke", "mining_service_smoke", "mining_authority_smoke",
)


def run(engine, output, name):
    folder = output / name
    folder.mkdir(parents=True)
    log = folder / "godot.log"
    command = [engine, "--headless", "--path", str(adc.GAME), "--log-file", str(log)]
    if name == "crafting_service_smoke":
        command += ["--script", f"res://scripts/dev_tools/{name}.gd"]
    else:
        command += [f"res://scenes/dev_tools/{name}.tscn"]
    env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(folder / "adc"),
               AETHERIA_NATIVE_LOG=str(log))
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=120, env=env)
        text = result.stdout + result.stderr
        # Existing suites use both summary formats; neither engine exit alone nor
        # a PASS line may hide a script error or a failed assertion.
        counts = re.findall(r"\[[^\]\n]+\] (\d+) checks, (\d+) failures", text)
        legacy = re.findall(r"\[[^\]\n]+\] PASS: (\d+) checks\.", text)
        valid = ((len(counts) == 1 and int(counts[0][0]) > 0 and counts[0][1] == "0")
                 or (len(legacy) == 1 and int(legacy[0]) > 0))
        passed = result.returncode == 0 and valid and "ERROR:" not in text and "FAIL" not in text
        summary = counts or legacy
        exit_code = result.returncode
    except subprocess.TimeoutExpired as error:
        text, passed, summary, exit_code = f"Timed out: {error}\n", False, [], None
    adc.atomic(folder / "validation.log", text)
    adc.atomic(folder / "validation.json", dict(passed=passed, exit_code=exit_code, command=command))
    return name, passed, summary, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix="aetheria-starforged-"))
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda name: run(args.godot, output, name),
                                (*SCENES, "crafting_service_smoke")))
    for name, passed, summary, text in results:
        print(f"{name}: {'PASS' if passed else 'FAIL'} {summary}")
        if not passed:
            print(text)
    print(f"Validation evidence: {output}")
    return int(not all(result[1] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
