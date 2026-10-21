#!/usr/bin/env python3
"""Copy a character export into Godot without modifying the source export.

Run: python tools/import_character_sprites.py "C:/Users/Riptide/Desktop/Character Sprites"
The importer needs only Python's standard library; --contact-sheet additionally
uses Pillow. --check verifies the existing import without writing any files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = (
    "south", "south-east", "east", "north-east", "north",
    "north-west", "west", "south-west",
)
ROLES = ("idle", "walk", "attack")


def definition(skin_id, name, height, feet, monsters=(), animations=None):
    return {"skin_id": skin_id, "name": name, "display_height": height,
            "foot_y": feet, "monsters": monsters, "animation_roles": animations or {}}


# Explicit semantic assignments: export folder names are generic and may change.
# IDs identify original character states, not export ordering or filenames.
KNOWN_STATES = {
    "16f5d16e-6e85-4a19-8a93-382c8398d82b": definition(
        "golem_titan", "Golem Titan", 80, 57, ("Golem Titan",),
        {"The_golem_raises_both_heavy_fists_high_above_its_h": "attack"}),
    "218d6657-45c8-4f1d-91d2-0ea5b75bf96c": definition(
        "golem_runeshell", "Golem Runeshell", 64, 57, ("Golem Runeshell",)),
    "d54942ca-46ea-4c74-8573-21638f4d453f": definition(
        "golem_crystalcore", "Golem Crystalcore", 60, 66, ("Golem Crystalcore",)),
    "35fc8022-b470-4d09-ad9b-f2a81e2422e3": definition(
        "golem_stoneguard", "Golem Stoneguard", 56, 66,
        ("Golem Boulderkin", "Golem Stoneguard")),
    "541ed12a-5fc7-43aa-a205-310a8f955a34": definition(
        "golem_shardling", "Golem Shardling", 36, 55, ("Golem Shardling",),
        {"Walking": "walk"}),
    "723ffe6c-f28f-42b6-a37d-584b83db8c6c": definition(
        "peasant", "Peasant", 48, 58, animations={"Running": "walk"}),
    "d9928773-a272-4ff5-9735-126b050e7f8e": definition(
        "peasant_sword", "Peasant with Iron Longsword", 48, 58,
        animations={"Walking": "walk"}),
    "59a206ee-f71f-4505-a04b-d30eeeebf885": definition(
        "wolf_direwolf", "Wild Direwolf", 56, 63, ("Wolf Direwolf",)),
    "b813b8e7-c0fc-42f5-b649-96295dd1965f": definition(
        "wolf_moonfang", "White Two-Tailed Wolf", 56, 61,
        ("Wolf Moonfang", "Wolf Elder Fang"),
        {"The_creature_maintains_a_steady_idle_stance_while": "idle"}),
    "b9ab5076-0855-4cf2-a335-27000ba3ef49": definition(
        "wraith_soulpiercer", "Wraith Soulpiercer", 56, 60,
        ("Wraith Soulpiercer",)),
    "44f24c96-1a12-467f-b7c4-5c0b6a65394d": definition(
        "wraith_dreadshade", "Wraith Dreadshade", 64, 60,
        ("Wraith Dreadshade",)),
    "5c79ab8e-464d-4597-a7ed-2abf40fcc1dc": definition(
        "skeleton_footsoldier", "Skeleton Footsoldier", 48, 56,
        ("Skeleton Footsoldier",)),
    "602efcb3-e717-4c54-bd93-63df748c9a9f": definition(
        "skeleton_knight", "Skeleton Knight", 52, 56, ("Skeleton Knight",)),
    "b68ad133-4622-4f87-8b68-59c1ec78ca73": definition(
        "skeleton_acolyte", "Skeleton Acolyte", 50, 53, ("Skeleton Acolyte",)),
    "6aff34b7-7aca-48df-bb31-e9f9e66433e6": definition(
        "skeleton_captain", "Skeleton Captain", 56, 54, ("Skeleton Captain",)),
    "69a9fbec-405d-4e88-ba7c-a355defcdc8b": definition(
        "slime_oozelord", "Slime Oozelord", 54, 58, ("Slime Oozelord",)),
    "d215ffc4-b805-4a89-a6c3-3d3a0c2944e4": definition(
        "slime_gelwarden", "Slime Gelwarden", 52, 56, ("Slime Gelwarden",),
        {"Walking": "walk"}),
    "e8c509a6-6216-43ee-9e43-38a396152113": definition(
        "slime_caustic", "Green Slime", 40, 57,
        ("Slime Glob", "Slime Puddle", "Slime Caustic"),
        {"idle_animation_green_slime_monster_pulsing_spikes": "idle"}),
    "888f967f-f4b6-42d5-a6fa-a4989349d179": definition(
        "goblin_scout", "Goblin Scout", 44, 55, ("Goblin Scout",)),
    "dd308266-39ee-481b-9d23-906d0d964bee": definition(
        "goblin_worker", "Goblin Worker", 44, 53, ("Goblin Worker",)),
    "22405917-2761-4b8f-8c6f-15a071f39a37": definition(
        "goblin_warrior", "Goblin Warrior", 46, 52, ("Goblin Warrior",)),
    "002dc472-b405-4b99-bc49-a2561c5fda7e": definition(
        "goblin_shaman", "Goblin Shaman", 46, 52, ("Goblin Shaman",)),
    "50e00ee8-469f-46fd-b8a0-73adc007d361": definition(
        "goblin_chieftain", "Goblin Chieftain", 56, 58, ("Goblin Chieftain",)),
}

# This export contains two separately generated west-facing idle takes. Both are
# copied and retained in exported_animations; the chosen take gets canonical west.
DIRECTION_ALIASES = {"west-5e3d6f1d": "west", "west-b799e8a2": "west"}
PREFERRED_VARIANTS = {("wolf_moonfang", "idle", "west"): "west-5e3d6f1d"}


def slug(value):
    return re.sub(r"[^a-z0-9_-]+", "_", value.lower()).strip("_") or "animation"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_fingerprint(source_root, sources):
    checksum = hashlib.sha256()
    for source in sorted(set(sources)):
        checksum.update(source.relative_to(source_root).as_posix().encode("utf-8"))
        checksum.update(b"\0")
        checksum.update(bytes.fromhex(digest(source)))
    return checksum.hexdigest()


def safe_source(root, reference):
    relative = PurePosixPath(reference)
    if relative.is_absolute() or ".." in relative.parts or "\\" in reference:
        raise ValueError(f"Unsafe export path: {reference!r}")
    target = (root / Path(*relative.parts)).resolve()
    if not target.is_relative_to(root) or target.suffix.lower() != ".png":
        raise ValueError(f"Invalid PNG reference: {reference!r}")
    if not target.is_file():
        raise ValueError(f"Missing source frame: {reference}")
    return target


def png_size(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Invalid PNG: {path}")
    return struct.unpack(">II", header[16:24])


def collect_states(metadata):
    records = [state for group in metadata.get("groups", [])
               for state in group.get("states", [])] + metadata.get("states", [])
    unique = {}
    for state in records:
        character_id = state["character"]["id"]
        if character_id in unique:
            if unique[character_id] != state:
                raise ValueError(f"Conflicting duplicate character state {character_id}")
            continue
        unique[character_id] = state
    if not unique:
        raise ValueError("Export metadata contains no character states")
    return list(unique.values()), len(records)


def build_catalog(source_root, client_root):
    metadata_path = source_root / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8-sig"))
    states, record_count = collect_states(metadata)
    monsters = json.loads((client_root / "data/monsters.json").read_text(encoding="utf-8-sig"))
    monster_names = {monster["name"] for monster in monsters}
    copy_plan = {}
    frame_dimensions = {}
    skins = {}
    monster_skins = {}
    source_frame_count = 0

    def frame(reference, destination, size, rotation=False):
        source = safe_source(source_root, reference)
        dimensions = png_size(source)
        if rotation and dimensions != tuple(size):
            raise ValueError(f"Frame size disagrees with character metadata: {reference}")
        destination = client_root / "Assets/Characters" / destination
        if destination in copy_plan and copy_plan[destination] != source:
            raise ValueError(f"Output frame collision: {destination}")
        copy_plan[destination] = source
        resource = "res://" + destination.relative_to(client_root).as_posix()
        frame_dimensions[resource] = list(dimensions)
        return resource

    for state in states:
        character = state["character"]
        character_id = character["id"]
        size = [int(character["size"][axis]) for axis in ("width", "height")]
        config = KNOWN_STATES.get(character_id) or definition(
            "character_" + character_id.replace("-", ""), character.get("name", "Character"),
            48, size[1])
        skin_id = config["skin_id"]
        if skin_id in skins:
            raise ValueError(f"Duplicate stable skin ID: {skin_id}")
        rotations = {}
        for direction, reference in state["frames"].get("rotations", {}).items():
            if direction not in DIRECTIONS:
                raise ValueError(f"Unknown rotation direction {direction} for {skin_id}")
            rotations[direction] = frame(reference, Path(skin_id)/"rotations"/(direction+".png"), size, rotation=True)
            source_frame_count += 1
        missing_rotations = [direction for direction in DIRECTIONS if direction not in rotations]
        if missing_rotations:
            raise ValueError(f"{skin_id} is missing rotations: {missing_rotations}")

        animations = {}
        exported_animations = {}
        unassigned = []
        for source_name, source_directions in state["frames"].get("animations", {}).items():
            role = config["animation_roles"].get(source_name)
            if role and role not in ROLES:
                raise ValueError(f"Unknown configured animation role {role}")
            destination_name = role or slug(source_name)
            exported = {}
            candidates = {}
            for source_direction, references in source_directions.items():
                if not references:
                    raise ValueError(f"Empty exported animation: {skin_id}/{source_name}/{source_direction}")
                paths = [frame(reference,
                               Path(skin_id)/"animations"/destination_name/slug(source_direction)/f"frame_{i:03}.png",
                               size) for i, reference in enumerate(references)]
                source_frame_count += len(paths)
                exported[source_direction] = paths
                canonical = DIRECTION_ALIASES.get(source_direction, source_direction)
                if canonical not in DIRECTIONS:
                    if role:
                        raise ValueError(f"Unrecognized animation direction: {source_direction}")
                    continue
                candidates.setdefault(canonical, []).append((source_direction, paths))
            exported_animations[source_name] = exported
            if role:
                if role in animations:
                    raise ValueError(f"Multiple animations assigned to {skin_id}/{role}; select one explicitly")
                selected = {}
                for direction in DIRECTIONS:
                    if direction not in candidates:
                        continue
                    alternatives = candidates[direction]
                    preferred = PREFERRED_VARIANTS.get((skin_id, role, direction), direction)
                    chosen = next((paths for source_direction, paths in alternatives
                                   if source_direction == preferred), None)
                    if chosen is None:
                        if len(alternatives) > 1:
                            raise ValueError(f"Ambiguous animation takes: {skin_id}/{role}/{direction}")
                        chosen = alternatives[0][1]
                    selected[direction] = chosen
                animations[role] = {"fps": 10 if role == "walk" else 8,
                                    "loop": role != "attack", "directions": selected}
            else:
                unassigned.append(source_name)

        skins[skin_id] = {
            "name": config["name"], "source_character_id": character_id,
            "source_state_name": character.get("name", ""), "source_folder": state.get("folder", ""),
            "source_prompt": character.get("prompt", ""), "size": size,
            "display_height": config["display_height"], "foot_position": [size[0] / 2, config["foot_y"]],
            "rotations": rotations, "animations": animations,
            "exported_animations": exported_animations,
            "frame_sizes": {resource: dimensions for resource, dimensions in frame_dimensions.items()
                            if resource.startswith("res://Assets/Characters/" + skin_id + "/")},
            "coverage": {
                "rotation_directions": [direction for direction in DIRECTIONS if direction in rotations],
                "animated_directions": {
                    role: [direction for direction in DIRECTIONS
                           if direction in animations.get(role, {}).get("directions", {})]
                    for role in ROLES},
                "unassigned_animations": unassigned,
            },
        }
        for monster_name in config["monsters"]:
            if monster_name not in monster_names:
                raise ValueError(f"Mapped monster no longer exists: {monster_name}")
            if monster_name in monster_skins:
                raise ValueError(f"Duplicate monster mapping: {monster_name}")
            monster_skins[monster_name] = skin_id

    player_skins = [skin_id for skin_id in ("peasant", "peasant_sword") if skin_id in skins]
    if not player_skins:
        raise ValueError("Export does not include a supported player character")
    catalog = {
        "schema_version": 1, "directions": list(DIRECTIONS),
        "defaults": {"player": player_skins[0]}, "player_skins": player_skins,
        "equipment_skins": {"Iron Longsword": "peasant_sword"} if "peasant_sword" in skins else {},
        "monster_skins": dict(sorted(monster_skins.items())), "skins": skins,
        "import_summary": {
            "export_version": metadata.get("export_version"), "export_date": metadata.get("export_date"),
            "source_metadata_sha256": digest(metadata_path), "source_state_records": record_count,
            "source_assets_sha256": source_fingerprint(source_root, copy_plan.values()),
            "unique_states": len(states), "duplicate_state_records": record_count - len(states),
            "referenced_pngs": len(copy_plan), "source_frame_references": source_frame_count,
            "rotation_frames": sum(len(skin["rotations"]) for skin in skins.values()),
            "exported_animation_frames": sum(
                len(paths) for skin in skins.values() for animation in skin["exported_animations"].values()
                for paths in animation.values()),
            "mapped_monsters": len(monster_skins),
            "unmapped_monsters": sorted(monster_names - set(monster_skins)),
            "fallback_policy": "Use the exact-facing action when present, otherwise the exact-facing rotation. Never borrow another facing or generate missing frames.",
        },
    }
    return catalog, copy_plan


def contact_sheet(catalog, client_root, destination):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as error:
        raise ValueError("--contact-sheet requires Pillow; the normal importer does not") from error
    skins = list(catalog["skins"].values())
    columns, cell_w, cell_h = 5, 220, 170
    sheet = Image.new("RGB", (columns * cell_w, ((len(skins)+columns-1)//columns)*cell_h), "#181c24")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    for index, skin in enumerate(skins):
        x, y = index % columns * cell_w, index // columns * cell_h
        source = client_root / skin["rotations"]["south"].removeprefix("res://")
        with Image.open(source) as image:
            image = image.convert("RGBA")
            # Preserve aspect ratio, integer enlargement, and hard pixel edges.
            scale = max(1, min(128 // image.width, 128 // image.height))
            image = image.resize((image.width*scale, image.height*scale), Image.Resampling.NEAREST)
            sheet.paste(image, (x+(cell_w-image.width)//2, y+8+(128-image.height)), image)
        draw.text((x+10, y+143), skin["name"], fill="white", font=font)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Character export folder containing metadata.json")
    parser.add_argument("--client-root", type=Path, default=PROJECT_ROOT / "godot_client")
    parser.add_argument("--check", action="store_true", help="Verify imported catalog and every PNG without writing")
    parser.add_argument("--contact-sheet", action="store_true", help="Create docs/SpriteContactSheet.png (requires Pillow)")
    args = parser.parse_args()
    try:
        source_root, client_root = args.source.resolve(), args.client_root.resolve()
        if source_root == client_root or source_root.is_relative_to(client_root) or client_root.is_relative_to(source_root):
            raise ValueError("Source export and Godot destination must be separate folders")
        catalog, copy_plan = build_catalog(source_root, client_root)
        catalog_path = client_root / "data/character_sprites.json"
        catalog_text = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
        problems = []
        changed = 0
        for destination, source in copy_plan.items():
            matches = destination.is_file() and digest(destination) == digest(source)
            if args.check:
                if not matches:
                    problems.append(f"Missing or changed imported frame: {destination}")
            elif not matches:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                changed += 1
        if args.check:
            if not catalog_path.is_file() or catalog_path.read_text(encoding="utf-8") != catalog_text:
                problems.append(f"Catalog is missing or out of date: {catalog_path}")
            if problems:
                raise ValueError("\n".join(problems))
        else:
            catalog_path.parent.mkdir(parents=True, exist_ok=True)
            if not catalog_path.is_file() or catalog_path.read_text(encoding="utf-8") != catalog_text:
                catalog_path.write_text(catalog_text, encoding="utf-8", newline="\n")
            if args.contact_sheet:
                contact_sheet(catalog, client_root, PROJECT_ROOT / "docs/SpriteContactSheet.png")
        # The export is read-only input: verify its metadata and every referenced
        # original PNG are byte-identical after copying/checking.
        if digest(source_root / "metadata.json") != catalog["import_summary"]["source_metadata_sha256"]:
            raise ValueError("Source metadata changed during import")
        if source_fingerprint(source_root, copy_plan.values()) != catalog["import_summary"]["source_assets_sha256"]:
            raise ValueError("Source PNGs changed during import")
        summary = catalog["import_summary"]
        action = "Verified" if args.check else "Imported"
        print(f"{action} {summary['unique_states']} character states, {summary['referenced_pngs']} PNGs "
              f"({summary['rotation_frames']} rotations, {summary['exported_animation_frames']} animation frames); "
              f"{summary['mapped_monsters']} monster mappings; {summary['duplicate_state_records']} duplicate state records deduplicated.")
        if not args.check:
            print(f"Copied {changed} changed PNGs. Catalog: {catalog_path}")
        print(f"{len(summary['unmapped_monsters'])} monster definitions have no matching supplied character skin.")
        return 0
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        print(f"Sprite import failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
