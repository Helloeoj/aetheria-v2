#!/usr/bin/env python3
"""Measure the original head against each generated replacement pose, at 1x.

bodyOffset is the raw native source registration, for resolved actor markers.
headOffset adds only a reviewed 0..2px vertical mask-contact adjustment. It moves
the complete original head, never the full-frame authored chest/legs artwork.
Existing hands, handPixels, source and all unrelated fields are preserved.

Run with --write to update poses.json; --check checks a normal rebuild. Optional
--head-masks DIR reviews actual exported runtime head masks (<dir>/0.0-idle.png,
<dir>/0.0.png ... 7.0.png). It is not needed for normal rebuilds: previously
reviewed vertical contact adjustments are retained in the checked-in offsets.
--report FILE writes deterministic evidence outside the asset pack. PNGs are
always read-only. Requires Pillow, as do the other native artwork tools.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "godot_client/Assets/Equipment/fitted_bronze_iron"


def read_rgba(path: Path) -> Image.Image:
    with Image.open(path) as image:
        if image.size != (80, 80):
            raise ValueError(f"Expected native 80x80 canvas: {path}")
        return image.convert("RGBA")


def register_head(original: Image.Image, generated: Image.Image) -> dict:
    """Match the upper 16 native head rows, excluding independently drawn arms.

    Alpha disagreement costs 1000 per opaque/transparent pixel, greater than
    the maximum RGB distance (765). RGB distances distinguish facial/hair pose
    details despite the generation export's small palette conversion. No image
    scaling, interpolation, centering, or directional mirroring is performed.
    """
    first = original.getchannel("A").getbbox()[1]
    # The transparent border participates so a shifted silhouette cannot win
    # by matching only its interior. Search remains inside the native canvas.
    samples = [(x, y, original.getpixel((x, y)))
               for y in range(4, first + 16) for x in range(8, 72)]
    pixels = generated.load()
    ranked = []
    for dy in range(-4, 5):
        for dx in range(-8, 9):
            score = 0
            disagreements = 0
            for x, y, old in samples:
                new = pixels[x + dx, y + dy]
                if bool(old[3]) != bool(new[3]):
                    score += 1000
                    disagreements += 1
                if old[3] and new[3]:
                    score += sum(abs(old[c] - new[c]) for c in range(3))
            ranked.append((score, abs(dx) + abs(dy), dy, dx, disagreements))
    ranked.sort()
    score, _, dy, dx, disagreements = ranked[0]
    return {"offset": [dx, dy], "score": score,
            "runnerUpScore": ranked[1][0], "alphaDisagreements": disagreements,
            "sampleBounds": [8, 4, 72, first + 16]}


def mask_contact(head: Image.Image, chest: Image.Image, neck: list,
                 offset: list) -> dict:
    """Review only the native neckline, not distant cape/shoulder intersections."""
    nx, ny = (neck[i] + offset[i] for i in range(2))
    armor = [(x, y) for y in range(max(0, ny - 3), min(80, ny + 7))
             for x in range(max(0, nx - 5), min(80, nx + 6))
             if chest.getpixel((x, y))[3]]
    candidates = []
    for extra in range(3):
        pixels = [(x + offset[0], y + offset[1] + extra)
                  for y in range(80) for x in range(80)
                  if head.getpixel((x, y))[3]
                  and abs(x + offset[0] - nx) <= 5
                  and ny - 3 <= y + offset[1] + extra <= ny + 6]
        distance = min((max(abs(x - a), abs(y - b))
                        for x, y in pixels for a, b in armor), default=80)
        candidates.append(distance)
    extra = next((i for i, distance in enumerate(candidates) if distance <= 1), 0)
    return {"additionalY": extra, "necklineDistances": candidates,
            "contactFound": candidates[extra] <= 1}


def build(pack: Path = PACK, head_masks: Path | None = None) -> tuple[dict, dict]:
    poses = json.loads((pack / "replacement-v1/poses.json").read_text())
    rigs = json.loads((pack / "rigs.json").read_text())["rigs"]
    result = deepcopy(poses)
    evidence = {"metric": "native-rgba-upper-head-v1", "canvas": [80, 80],
                "searchBounds": [-8, -4, 8, 4], "poses": []}
    for direction, actions in result.items():
        for action, frames in actions.items():
            for index, pose in frames.items():
                source_index = int(index) + 1 if action == "run" else 0
                original_path = pack / "original" / direction / f"{source_index}.png"
                generated_path = pack / pose["source"]
                measured = register_head(read_rgba(original_path), read_rgba(generated_path))
                offset = measured["offset"]
                old_body = pose.get("bodyOffset", offset)
                extra = (pose.get("headOffset", offset)[1] - old_body[1]
                         if "bodyOffset" in pose else 0)
                if extra not in (0, 1, 2):
                    raise ValueError(f"Invalid reviewed head-contact adjustment: {direction}/{action}/{index}")
                row = {"direction": direction, "action": action, "frame": int(index),
                       "original": original_path.relative_to(pack).as_posix(),
                       "source": pose["source"], **measured,
                       "originalSha256": hashlib.sha256(original_path.read_bytes()).hexdigest(),
                       "sourceSha256": hashlib.sha256(generated_path.read_bytes()).hexdigest()}
                if head_masks is not None:
                    mask_path = head_masks / direction / (f"{index}.0.png" if action == "run" else "0.0-idle.png")
                    chest_path = pack / "replacement-v1/iron/chest" / direction / f"{source_index}.png"
                    neck = rigs[direction]["frames"][source_index]["joints"]["neck"]
                    review = mask_contact(read_rgba(mask_path), read_rgba(chest_path), neck, offset)
                    extra = review["additionalY"]
                    row["maskReview"] = {**review, "sha256": hashlib.sha256(mask_path.read_bytes()).hexdigest()}
                pose["bodyOffset"] = offset
                pose["headOffset"] = [offset[0], offset[1] + extra]
                row["headOffset"] = pose["headOffset"]
                evidence["poses"].append(row)
    if len(evidence["poses"]) != 72:
        raise ValueError("The replacement actor must have eight idle and 64 walk poses")
    return result, evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, default=PACK)
    parser.add_argument("--head-masks", type=Path)
    parser.add_argument("--report", type=Path)
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--write", action="store_true")
    operation.add_argument("--check", action="store_true")
    args = parser.parse_args()
    poses, evidence = build(args.pack, args.head_masks)
    path = args.pack / "replacement-v1/poses.json"
    if args.check and poses != json.loads(path.read_text()):
        raise SystemExit("Pose anchors differ from the native source measurements")
    if args.write:
        path.write_text(json.dumps(poses, indent=2) + "\n", encoding="utf-8")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"Measured {len(evidence['poses'])} native pose anchors; "
          f"{'updated' if args.write else 'checked' if args.check else 'read-only'}.")


if __name__ == "__main__":
    main()
