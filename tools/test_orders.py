"""Run real Godot Orders framework tests; keep all machine evidence outside Git."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SUITES = {
    "generation": ("scene", "res://scenes/dev_tools/orders_generation_smoke.tscn", r"\[Orders generation\] (\d+) checks, 0 failures"),
    "reader": ("scene", "res://scenes/dev_tools/orders_reader_smoke.tscn", r"\[Orders reader\] (\d+) checks, 0 failures"),
    "inventory": ("scene", "res://scenes/dev_tools/orders_inventory_smoke.tscn", r"\[Orders inventory\] (\d+) checks, 0 failures"),
    "definitions": ("--script", "res://scripts/dev_tools/orders_definitions_smoke.gd", r"\[Orders definitions\] (\d+) checks, 0 failures"),
    "rules": ("scene", "res://scenes/dev_tools/orders_rules_smoke.tscn", r"\[Orders rules\] (\d+) checks, 0 failures"),
    "authority": ("scene", "res://scenes/dev_tools/orders_authority_smoke.tscn", r"\[Orders authority\] (\d+) checks, 0 failures"),
    "activities": ("scene", "res://scenes/dev_tools/orders_activities_smoke.tscn", r"\[Orders activities\] (\d+) checks, 0 failures"),
    "ui": ("scene", "res://scenes/dev_tools/orders_ui_smoke.tscn", r"\[Orders UI\] (\d+) checks, 0 failures"),
    "codec": ("scene", "res://scenes/dev_tools/character_persistence_smoke.tscn", r"\[Character persistence\] (\d+) checks, 0 failures"),
    "host": ("scene", "res://scenes/dev_tools/world_host_persistence_smoke.tscn", r"\[World host persistence\] (\d+) checks, 0 failures"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--suite", choices=["all", *SUITES], default="all")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="aetheria-orders-"))
    output.mkdir(parents=True, exist_ok=True)
    selected = SUITES if args.suite == "all" else {args.suite: SUITES[args.suite]}
    results = []
    for name, (mode, target, marker) in selected.items():
        log = output / f"{name}-native.log"
        cmd = [args.godot, "--headless", "--path", str(ROOT / "godot_client"), "--log-file", str(log)]
        if mode == "--script":
            cmd.append(mode)
        cmd.extend([target, "--", "--social-no-auto"])
        env = dict(os.environ, AETHERIA_DIAGNOSTICS_DIR=str(output / f"{name}-adc"))
        try:
            run = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=env)
            text = run.stdout + run.stderr
            matched = re.search(marker, text)
            passed = run.returncode == 0 and matched is not None and int(matched.group(1)) > 0 and not re.search(r"(?:SCRIPT ERROR:|(?m:^ERROR:))", text)
            exit_code = run.returncode
        except subprocess.TimeoutExpired as exc:
            text = f"Timed out: {exc}"
            passed, exit_code = False, -1
        (output / f"{name}.log").write_text(text, encoding="utf-8")
        results.append({"suite": name, "passed": passed, "exit_code": exit_code, "command": cmd})
        print(f"{name}: {'PASS' if passed else 'FAIL'}", flush=True)
        if not passed:
            print(text[-6000:], flush=True)
    (output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"Evidence: {output}", flush=True)
    return int(any(not result["passed"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
