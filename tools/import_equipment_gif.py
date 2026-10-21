"""Decode an eight-view equipment GIF to PNGs without changing its RGBA pixels.

The GIF is an orbit preview: its frames are directions, not an animation clip.
Pillow is required. The original input is read-only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


DIRECTIONS = (
    "south", "south-east", "east", "north-east",
    "north", "north-west", "west", "south-west",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true", help="Compare existing PNGs without writing files")
    args = parser.parse_args()
    source_bytes = args.source.read_bytes()
    source_hash = hashlib.sha256(source_bytes).hexdigest()
    manifest = {
        "source_filename": args.source.name,
        "source_sha256": source_hash,
        "direction_order": list(DIRECTIONS),
        "conversion": "Decoded original RGBA pixels; native GIF transparency preserved. No resizing, mirroring or recoloring.",
        "frames": [],
    }
    if not args.check:
        args.output.mkdir(parents=True, exist_ok=True)
    with Image.open(args.source) as gif:
        if gif.format != "GIF" or gif.n_frames != 8:
            raise ValueError("Expected an eight-view GIF; direction order must be reviewed before importing other layouts.")
        for index, direction in enumerate(DIRECTIONS):
            gif.seek(index)
            original = gif.convert("RGBA")
            output_path = args.output / f"{direction}.png"
            if not args.check:
                original.save(output_path)
            with Image.open(output_path) as result:
                if result.size != original.size or result.convert("RGBA").tobytes() != original.tobytes():
                    raise ValueError(f"RGBA pixels differ from GIF frame {index}: {output_path}")
            manifest["frames"].append({
                "direction": direction,
                "gif_frame": index,
                "png": output_path.name,
                "size": list(original.size),
                "duration_ms": int(gif.info.get("duration", 0)),
                "rgba_sha256": hashlib.sha256(original.tobytes()).hexdigest(),
                "alpha_range": list(original.getchannel("A").getextrema()),
            })
    manifest_text = json.dumps(manifest, indent=2) + "\n"
    manifest_path = args.output / "source_manifest.json"
    if args.check:
        if manifest_path.read_text(encoding="utf-8") != manifest_text:
            raise ValueError("Source manifest differs from the original GIF.")
    else:
        manifest_path.write_text(manifest_text, encoding="utf-8")
    if hashlib.sha256(args.source.read_bytes()).hexdigest() != source_hash:
        raise ValueError("Source GIF changed during import.")
    print(f"[Equipment import] PASS: 8 directional PNGs match every source RGBA pixel; original GIF unchanged ({source_hash}).")


if __name__ == "__main__":
    main()
