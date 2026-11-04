"""Install the shared native128 ore artwork without changing its world geometry.

Default/--check validates and plans only. --apply is deliberately explicit.
This automatic gate does not certify visual approval or real Godot rendering.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path("godot_client/Assets/MapTiles/OreNodes/manifest.json")
TARGET = "res://Assets/MapTiles/OreNodes/Detail128/"


def digest(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def scene_with_detail(text: str, old_texture: str) -> str:
    """Only the Sprite2D gains a density transform; roots/bases stay byte-identical."""
    return text.replace(old_texture, TARGET + Path(old_texture).name).replace(
        "position = Vector2(-48, -72)\n",
        "position = Vector2(-48, -72)\nscale = Vector2(0.75, 0.75)\n"
        "metadata/native_image_anchor = Vector2(64, 96)\n")


def texture_import(resource: str) -> str:
    cache = "res://.godot/imported/" + Path(resource).name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".ctex"
    return ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
            f'path="{cache}"\nmetadata={{\n"vram_texture": false\n}}\n\n'
            f'[deps]\n\nsource_file="{resource}"\ndest_files=["{cache}"]\n\n'
            '[params]\n\ncompress/mode=0\ncompress/high_quality=false\n'
            'compress/lossy_quality=0.7\ncompress/hdr_compression=1\ncompress/normal_map=0\n'
            'mipmaps/generate=false\nmipmaps/limit=-1\nprocess/fix_alpha_border=false\n'
            'process/premult_alpha=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n')


def check_silhouette(alpha: np.ndarray, label: str) -> None:
    if not np.isin(alpha, [0, 255]).all():
        raise ValueError(f"{label}: alpha must be binary; opaque pixels cannot be blurry")
    visible = alpha > 0
    if not visible.any() or visible[0].any() or visible[-1].any() or visible[:, 0].any() or visible[:, -1].any():
        raise ValueError(f"{label}: empty or clipped whole silhouette")
    remaining = set(zip(*np.nonzero(visible)))
    while remaining:
        seed = remaining.pop()
        pending, count = [seed], 0
        while pending:
            y, x = pending.pop()
            count += 1
            neighbors = {(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1)} & remaining
            remaining.difference_update(neighbors)
            pending.extend(neighbors)
        if count < 3:
            raise ValueError(f"{label}: disconnected stray silhouette component ({count} pixels)")


def install(repo: Path = ROOT, source: Path | None = None, *, apply: bool = False) -> dict:
    repo = Path(repo).resolve()
    source = Path(source).resolve() if source else repo / "art_sources/ore-nodes/detail-v1"
    support = repo / "tools/ore-integration"
    baseline = json.loads((support / "original-library.json").read_text(encoding="utf-8"))
    originals = json.loads((support / "original-scenes.json").read_text(encoding="utf-8"))
    current = json.loads((repo / MANIFEST).read_text(encoding="utf-8"))
    if len(baseline["entries"]) != 10 or len(current["entries"]) != 10:
        raise ValueError("Expected the existing ten ore identities")
    writes: dict[Path, bytes] = {}
    depleted_bytes = None
    base = None
    images = []
    original_host = repo / "godot_client" / baseline["entries"][0]["depleted"]["texture"].removeprefix("res://")
    with Image.open(original_host) as old_image:
        # Preserve the original physical silhouette on the finer canvas. This
        # re-rasterizes its boundary rather than enlarging coarse edge steps.
        expected_alpha = np.array(old_image.getchannel("A").resize((128, 128), Image.Resampling.BILINEAR)) >= 128
    result = copy.deepcopy(baseline)
    result.update(version=2, native_canvas_size=[128, 128], world_canvas_size=[96, 96],
                  visual_scale=[0.75, 0.75], world_pixels_per_source_pixel=0.75,
                  source_art_directory="art_sources/ore-nodes/detail-v1",
                  spacing_guide="Unchanged root spacing: 96 world pixels compact; 128 beside routes. Native128 artwork occupies the original96-world-pixel canvas.",
                  anchor_note="Native image foot anchor (64,96) maps through Visual.scale .75 to world foot anchor (48,72). Visual.position remains (-48,-72); root scale remains 1.",
                  source_status="Native128 clarity artwork installed; automatic integrity checks do not confer artwork approval or Godot4x visual acceptance.")
    if set(current) - set(result):
        raise ValueError("Manifest contains unrecognized pending fields; refusing to discard unrelated work")
    for original, existing, entry in zip(baseline["entries"], current["entries"], result["entries"]):
        for key in ("id", "name", "collision_polygons"):
            if existing[key] != original[key]:
                raise ValueError(f"Manifest {key} changed outside the art-only contract")
        entry.update(anchor=[64, 96], world_anchor=[48, 72], native_canvas_size=[128, 128], visual_scale=[0.75, 0.75])
        if set(existing) - set(entry):
            raise ValueError("Manifest entry contains unrecognized pending fields; refusing to discard unrelated work")
        for key in ("anchor", "world_anchor", "native_canvas_size", "visual_scale"):
            if key in existing and existing[key] not in (original.get(key), entry.get(key)):
                raise ValueError(f"Manifest {key} changed outside the art-only contract")
        for state in ("full", "depleted"):
            old = original[state]
            if set(existing[state]) - set(old):
                raise ValueError("Manifest variant contains unrecognized pending fields; refusing to discard unrelated work")
            for key in ("scene", "tile_id"):
                if existing[state][key] != old[key]:
                    raise ValueError(f"Manifest {key} changed outside the art-only contract")
            old_path = repo / "godot_client" / old["texture"].removeprefix("res://")
            if digest(old_path.read_bytes()) != old["source_sha256"]:
                raise ValueError(f"{old_path.name}: original96 source was modified")
            source_path = source / old_path.name
            data = source_path.read_bytes()
            with Image.open(source_path) as image:
                if image.size != (128, 128) or image.mode != "RGBA":
                    raise ValueError(f"{source_path.name}: require native128x128 RGBA PNG")
                pixels = np.array(image)
            check_silhouette(pixels[:, :, 3], source_path.name)
            if not np.array_equal(pixels[:, :, 3] > 0, expected_alpha):
                raise ValueError(f"{source_path.name}: silhouette differs from the original96 boundary rerasterized128 (bilinear, threshold128)")
            if base is None and state == "depleted":
                base, depleted_bytes = pixels, data
            if state == "depleted" and data != depleted_bytes:
                raise ValueError("All depleted source files must be byte-identical shared host artwork")
            images.append((source_path.name, state, pixels))
            texture = TARGET + old_path.name
            entry[state].update(texture=texture, source_sha256=digest(data))
            target = repo / "godot_client" / texture.removeprefix("res://")
            writes[target] = data
            # Preserve engine-created UID/import fields on a repeat installation.
            import_path = target.with_suffix(".png.import")
            if import_path.exists():
                imported = import_path.read_text(encoding="utf-8")
                if "compress/mode=0" not in imported or "mipmaps/generate=false" not in imported:
                    raise ValueError(f"{target.name}: runtime import is not lossless/no-mipmap")
            else:
                writes[import_path] = texture_import(texture).encode()
            scene = repo / "godot_client" / old["scene"].removeprefix("res://")
            expected = scene_with_detail(originals[old["scene"]], old["texture"])
            text = scene.read_text(encoding="utf-8")
            if text not in (originals[old["scene"]], expected):
                raise ValueError(f"{old['scene']}: scene changed outside Visual texture/scale/native-anchor")
            writes[scene] = expected.encode()
    mask_path = source / "vein-mask.png"
    mask = None
    if mask_path.exists():
        with Image.open(mask_path) as image:
            if image.size != (128, 128):
                raise ValueError("Vein mask must be native128")
            mask = np.array(image.convert("L")) > 0
        if not mask.any() or (mask & (base[:, :, 3] == 0)).any():
            raise ValueError("Vein mask must stay inside the shared opaque host")
    inferred = None
    for name, state, pixels in images:
        if not np.array_equal(pixels[:, :, 3], base[:, :, 3]):
            raise ValueError(f"{name}: full/depleted alpha silhouettes must all match")
        difference = np.any(pixels[:, :, :3] != base[:, :, :3], axis=2)
        if (difference & (base[:, :, 3] == 0)).any():
            raise ValueError(f"{name}: transparent non-mineral host RGB changed")
        if state == "full":
            if not difference.any():
                raise ValueError(f"{name}: full ore must contain mineral pixels")
            if mask is not None and (difference & ~mask).any():
                raise ValueError(f"{name}: shared non-mineral host RGB changed outside vein mask")
            if mask is None:
                if inferred is None:
                    inferred = difference
                elif not np.array_equal(difference, inferred):
                    raise ValueError(f"{name}: mineral masks differ without an explicit shared vein-mask.png")
        elif difference.any():
            raise ValueError(f"{name}: depleted host differs")
    if len({digest((source / Path(e["full"]["texture"]).name).read_bytes()) for e in baseline["entries"]}) != 10:
        raise ValueError("All ten full mineral variants must be distinct")
    for key in ("spacing", "native_scale", "world_source_id", "standalone_source_id", "scene_collection", "world_tileset", "standalone_tileset", "texture_import", "gameplay_scope"):
        if current[key] != baseline[key]:
            raise ValueError(f"Manifest {key} changed outside the art-only contract")
    writes[repo / MANIFEST] = (json.dumps(result, indent=2) + "\n").encode()
    if apply:
        for path, data in writes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists() or path.read_bytes() != data:
                path.write_bytes(data)
    return {"mode": "applied" if apply else "check", "textures": 20, "scenes": 20,
            "native_canvas_size": [128, 128], "world_canvas_size": [96, 96],
            "world_pixels_per_source_pixel": 0.75, "world_anchor": [48, 72],
            "vein_mask": "explicit" if mask is not None else "shared inferred RGB difference",
            "silhouette": "original96 alpha rerasterized128 with bilinear threshold128; shared across all20",
            "collision_and_root_transforms": "unchanged against original snapshot",
            "visual_approval": "separate; not certified", "rendering_verified": False,
            "source_sha256": {path.name: digest(data) for path, data in writes.items() if path.suffix == ".png"}}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--source", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Default: validate with no writes")
    mode.add_argument("--apply", action="store_true", help="Apply validated art-only copies and references")
    args = parser.parse_args()
    try:
        print(json.dumps(install(args.repo, args.source, apply=args.apply), indent=2))
    except (ValueError, OSError) as error:
        parser.exit(1, f"Ore clarity gate failed: {error}\n")


if __name__ == "__main__":
    main()
