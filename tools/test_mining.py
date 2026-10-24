"""Run isolated Godot Mining tests; script errors fail even on a zero engine exit."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile

from test_cooking import run_scene

SCENES = (
    "mining_definitions_smoke", "mining_service_smoke",
    "mining_authority_smoke", "mining_host_smoke",
    "character_persistence_smoke", "region_freeze_smoke",
    "world_host_persistence_smoke",
    "original_online_minigames_smoke",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix="aetheria-mining-"))
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda scene: run_scene(args.godot, output, scene), SCENES))
    for scene, passed, counts, text in results:
        print(f"{scene}: {'PASS' if passed else 'FAIL'} {counts}")
        if not passed:
            print(text)
    print(f"Validation evidence: {output}")
    return int(not all(result[1] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
