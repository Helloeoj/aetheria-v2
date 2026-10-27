"""Read-only worldbuilding gate. Requires Pillow and the installed Godot 4.5.1.

python tools/worldbuilding.py --manifest tools/worldbuilding/example.json \
    --godot <installed-console-executable> --report <outside-repo>/audit.json
python tools/worldbuilding.py --self-test --godot <exe> --report <outside-repo>/tests.json

A green result proves the declared automatic checks, never visual approval.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot_client"
ENGINE_ERRORS = re.compile(r"SCRIPT ERROR:|(?m:^ERROR:)|\bFAIL(?:\]|:)")


def failure(code: str, detail: str) -> dict:
    return {"passed": False, "checks": 0, "issues": [{"code": code, "detail": detail}],
            "rendering_verified": False}


def require_external_report(path: Path, repository: Path = ROOT) -> None:
    if path.resolve().is_relative_to(repository.resolve()):
        raise ValueError("Keep generated reports outside the repository.")


def load_contract(path: Path, project: Path = PROJECT) -> dict:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict) or type(data.get("schema_version")) is not int or data["schema_version"] != 1:
        raise ValueError("schema_version must be integer 1.")
    scene = data.get("scene")
    if not isinstance(scene, str) or not scene.startswith("res://") or "\\" in scene:
        raise ValueError("scene must be a res:// PackedScene path.")
    candidate = (project / scene[6:]).resolve()
    if not candidate.is_relative_to(project.resolve()) or candidate.suffix != ".tscn" or not candidate.is_file():
        raise ValueError("scene must resolve to an existing .tscn inside the Godot project.")
    assets = data.get("assets")
    if not isinstance(assets, list) or not assets or any(not isinstance(asset, dict) for asset in assets):
        raise ValueError("assets must list the source-art contract for every changed prop type.")
    textures = set()
    for asset in assets:
        texture = asset.get("texture")
        density = asset.get("world_pixels_per_source_pixel", 1)
        if not isinstance(texture, str) or texture in textures:
            raise ValueError("assets require unique texture paths.")
        if type(density) not in (int, float) or not 0 < density <= 64 or not math.isfinite(density):
            raise ValueError("world_pixels_per_source_pixel must be finite and positive (maximum 64).")
        textures.add(texture)
    return data


def bind_visuals(assets: list, visuals: list) -> list:
    """Match actual installed sprites to checked source size/density/anchor."""
    if not isinstance(visuals, list) or not visuals:
        return [{"code": "missing_prop_textures", "detail": "Scene audit did not identify any actual prop PNGs."}]
    by_texture = {asset["texture"]: asset for asset in assets}
    issues = []
    for visual in visuals:
        if not isinstance(visual, dict):
            issues.append({"code": "invalid_prop_texture", "detail": "Malformed actual visual evidence."})
            continue
        asset = by_texture.get(visual.get("texture"))
        node = visual.get("node", "")
        if asset is None:
            issues.append({"code": "unchecked_prop_texture", "node": node, "detail": f"Actual sprite {visual.get('texture')} has no native-art contract."})
            continue
        if visual.get("native_size") != asset.get("native_size"):
            issues.append({"code": "imported_native_size", "node": node, "detail": f"Loaded Godot texture canvas {visual.get('native_size')}; checked source canvas {asset.get('native_size')}. Reimport the asset."})
        density = asset.get("world_pixels_per_source_pixel", 1)
        scale = visual.get("world_scale", [])
        if (not isinstance(scale, list) or len(scale) != 2 or any(
                type(value) not in (int, float) or not math.isfinite(value) or not math.isclose(value, density, abs_tol=0.0001)
                for value in scale)):
            issues.append({"code": "prop_density", "node": node, "detail": f"Actual source-pixel world scale {scale}; declared density {density}."})
        anchor = visual.get("anchor", [])
        expected = asset.get("anchor", [])
        if (not isinstance(anchor, list) or len(anchor) != 2 or len(expected) != 2 or any(
                type(value) not in (int, float) or not math.isfinite(value) or not math.isclose(value, expected[index], abs_tol=0.0001)
                for index, value in enumerate(anchor))):
            issues.append({"code": "prop_anchor", "node": node, "detail": f"Actual canvas foot anchor {anchor}; declared anchor {expected}."})
    return issues


def run_godot(engine: Path, project: Path, manifest: Path, report: Path) -> dict:
    # A fresh file is required even when Godot exits zero after a script error.
    report.unlink(missing_ok=True)
    command = [str(engine), "--headless", "--path", str(project), "--script",
               "res://tools/check_worldbuilding.gd", "--", "--manifest", str(manifest.resolve()),
               "--report", str(report.resolve())]
    try:
        process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                 errors="replace", timeout=55)
    except subprocess.TimeoutExpired:
        return failure("engine_timeout", "Godot exceeded 55 seconds; placement is not validated.")
    except OSError as exc:
        return failure("engine_unavailable", str(exc))
    output = process.stdout + process.stderr
    try:
        result = json.loads(report.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        result = failure("engine_report", "Godot did not produce a fresh valid placement report.")
    if not isinstance(result, dict):
        result = failure("engine_report", "Placement report must be an object.")
    if not isinstance(result.get("issues"), list) or type(result.get("checks")) is not int:
        result = failure("engine_report", "Placement report is missing checks/issues.")
    if ENGINE_ERRORS.search(output):
        result["issues"].insert(0, {"code": "engine_error", "detail": "Godot reported a script/engine error; inspect engine_output."})
    if process.returncode != 0 and not result["issues"]:
        result["issues"].append({"code": "engine_exit", "detail": f"Godot exited {process.returncode}."})
    result["passed"] = (result.get("passed") is True and process.returncode == 0
                        and result.get("checks", 0) > 0 and not result["issues"])
    if not result["passed"] and not result["issues"]:
        result["issues"].append({"code": "engine_report", "detail": "Incomplete or inconsistent placement report."})
    result["rendering_verified"] = False
    result["engine_output"] = output[-16000:]
    return result


def check_world(manifest: Path, engine: Path) -> dict:
    from prop_asset_check import check_asset
    spec = load_contract(manifest)
    assets = []
    issues = []
    for asset in spec["assets"]:
        result = check_asset(PROJECT, asset)
        result["texture"] = asset.get("texture")
        if result["checks"].get("png"):
            result["source_sha256"] = hashlib.sha256((PROJECT / asset["texture"][6:]).read_bytes()).hexdigest()
        assets.append(result)
        issues.extend(dict(issue, stage="asset", texture=asset.get("texture")) for issue in result["issues"])
    with tempfile.TemporaryDirectory(prefix="aetheria-worldbuilding-") as directory:
        geometry = run_godot(engine, PROJECT, manifest, Path(directory) / "geometry.json")
    issues.extend(dict(issue, stage="geometry") for issue in geometry["issues"])
    if all(asset["passed"] for asset in assets) and geometry["passed"]:
        issues.extend(dict(issue, stage="visual_binding") for issue in bind_visuals(spec["assets"], geometry.get("prop_textures")))
    return {"passed": not issues and all(asset["passed"] for asset in assets) and geometry["passed"],
            "scope": "declared assets, prop footprints, exact anchors and reserved routes only",
            "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
            "scene_sha256": hashlib.sha256((PROJECT / spec["scene"][6:]).read_bytes()).hexdigest(),
            "scene": spec["scene"], "assets": assets, "geometry": geometry, "issues": issues,
            "rendering_verified": False, "visual_review": "pending", "installation_approval": "not granted by this check"}


def self_test(engine: Path) -> dict:
    cases = [
        ("asset-and-runner", [sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", "test_*worldbuilding*.py"]),
        ("native-art", [sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", "test_prop_asset_check.py"]),
        ("live-physics", [str(engine), "--headless", "--path", str(PROJECT), "--script", "res://tools/worldbuilding_audit_test.gd"]),
        ("canonical-ore-library", [str(engine), "--headless", "--path", str(PROJECT), "--script", "res://tools/ore_node_library_smoke.gd"]),
    ]
    results = []
    for name, command in cases:
        try:
            process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                     encoding="utf-8", errors="replace", timeout=55)
            output = process.stdout + process.stderr
            passed = process.returncode == 0 and not ENGINE_ERRORS.search(output)
        except (subprocess.TimeoutExpired, OSError) as exc:
            output, passed = str(exc), False
        results.append({"name": name, "passed": passed, "output": output[-16000:]})
        print(f"{'PASS' if passed else 'FAIL'} {name}", flush=True)
    return {"passed": all(result["passed"] for result in results), "suites": results,
            "scope": "validator regression fixtures; does not certify installed world placements",
            "rendering_verified": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--manifest", type=Path)
    mode.add_argument("--self-test", action="store_true")
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True, help="Absolute JSON path outside repository")
    args = parser.parse_args()
    try:
        require_external_report(args.report)
    except ValueError as exc:
        parser.error(str(exc))
    try:
        result = self_test(args.godot) if args.self_test else check_world(args.manifest, args.godot)
    except (ValueError, OSError, ImportError) as exc:
        result = failure("contract_or_dependency", str(exc))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{'PASS' if result['passed'] else 'FAIL'} automatic checks; visual review remains separate. Report: {args.report.resolve()}")
    for issue in result.get("issues", []):
        print(f"  {issue.get('code')}: {issue.get('detail')}")
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
