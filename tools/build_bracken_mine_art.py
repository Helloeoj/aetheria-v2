"""Separate the approved native cave into editable terrain and reusable supplies.

Usage: python tools/build_bracken_mine_art.py [--prepare-pixel-base] [--preview /outside/repo/recomposed.png]
Requires Pillow and numpy for authoring only. Paths are repository-relative. This
does not generate, redraw, rescale or recolor the pixel-cleaned source. All masks
are bounded authored polygons; no color key or inferred walkability is used.
The geometry builder owns layout.json and all terrain collision independently.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot_client"
SOURCE = ROOT / "art_sources/bracken-mine/pixel-base.png"
OUT = PROJECT / "Assets/Maps/BrackenMine"
PROP_SCENES = PROJECT / "scenes/MapProps/BrackenMine"
WIDTH, HEIGHT, TILE = 1536, 1024, 32

# Coordinates follow visible silhouettes on the approved native master. Existing
# overlapping crates/barrel remain one whole assembly: a flat source cannot
# recover their hidden individual faces. No terrain mat or floor shadow travels
# with a prop. The donor offsets copy same-room floor only within each silhouette.
PROPS = [
    dict(name="MineCart", anchor=[1344, 320], donor_offset=[-112, 0],
         polygon=[[1330,268],[1338,268],[1348,274],[1356,280],[1364,284],
                  [1370,288],[1372,296],[1370,306],[1372,310],[1376,310],
                  [1380,318],[1378,324],[1366,328],[1358,324],[1356,320],
                  [1346,324],[1338,322],[1334,316],[1324,314],[1318,310],
                  [1314,310],[1308,302],[1308,292],[1310,288],[1306,286],
                  [1306,280],[1316,278],[1326,272]],
         collision=[[1314,294],[1328,288],[1364,304],[1374,316],
                    [1364,322],[1338,318],[1316,306]]),
    dict(name="SmallCrate", anchor=[1348, 260], donor_offset=[-96, 32],
         polygon=[[1334,242],[1342,238],[1350,238],[1358,242],[1360,248],
                  [1358,256],[1354,262],[1344,262],[1336,258],[1334,252]],
         collision=[[1336,250],[1346,246],[1358,250],[1356,260],[1344,262],
                    [1336,258]]),
    dict(name="SupplyStack", anchor=[1420, 342], donor_offset=[-832, 256],
         polygon=[[1362,236],[1378,228],[1388,232],[1398,238],[1400,244],
                  [1406,246],[1416,254],[1418,272],[1426,270],[1436,274],
                  [1444,280],[1446,290],[1444,302],[1444,310],[1450,316],
                  [1450,332],[1444,338],[1432,344],[1420,348],[1408,344],
                  [1398,338],[1394,328],[1394,316],[1398,306],[1404,304],
                  [1404,296],[1398,294],[1384,290],[1376,284],[1366,282],
                  [1358,278],[1354,270],[1354,260],[1358,258],[1358,244]],
         collision_parts=[
             [[1360,262],[1378,254],[1414,270],[1414,292],[1398,296],
              [1378,286],[1360,280]],
             [[1416,290],[1430,284],[1444,290],[1444,308],[1432,316],[1416,310]],
             [[1398,318],[1418,310],[1448,322],[1446,336],[1422,346],[1400,338]],
         ]),
]

# The loose crate touches the supply stack after the2px source export. Keep the
# visible group complete rather than fabricate the unavailable overlapping back.
_adjacent_crate = PROPS.pop(1)
PROPS[1]["mask_polygons"] = [_adjacent_crate["polygon"], PROPS[1]["polygon"]]
PROPS[1]["collision_parts"].append(_adjacent_crate["collision"])

# These are continuous rock/terrain bands, not independently invented rock props.
# They intersect the authored exterior/central-island masks. A tile's explicit
# sort origin anchors the whole band at its floor-side base while retaining its
# exact source UV. Players on the southern side then sort in front of its face.
FOREGROUND = [
    dict(name="CentralIsland", foot_y=582, polygon=[[620,268],[1054,268],[1054,596],[620,596]]),
    dict(name="NorthEastNearWall", foot_y=444,
         polygon=[[1150,334],[1206,314],[1320,310],[1414,336],[1494,328],
                  [1536,370],[1536,444],[1200,444],[1150,412]]),
    dict(name="WestNearWall", foot_y=748,
         polygon=[[0,492],[64,520],[104,548],[166,564],[246,572],[314,568],
                  [382,536],[418,528],[462,556],[496,608],[550,650],
                  [586,706],[564,754],[294,764],[88,680],[0,612]]),
    dict(name="SouthEastNearWall", foot_y=830,
         polygon=[[1096,654],[1182,668],[1246,698],[1322,712],[1418,708],
                  [1486,660],[1536,658],[1536,834],[1154,834],[1096,762]]),
    dict(name="SouthWestApproach", foot_y=966,
         polygon=[[298,896],[382,824],[498,780],[566,746],[592,722],
                  [654,738],[714,804],[726,868],[710,936],[674,976],
                  [310,980]]),
    dict(name="SouthEastApproach", foot_y=980,
         polygon=[[812,792],[902,734],[952,660],[1008,610],[1080,564],
                  [1110,576],[1140,630],[1092,730],[1044,792],[1132,846],
                  [1238,910],[1254,982],[850,992]]),
]


def json_write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def polygon_mask(points, pixel_blocks=False):
    factor = 2 if pixel_blocks else 1
    result = Image.new("L", (WIDTH // factor, HEIGHT // factor))
    ImageDraw.Draw(result).polygon([(x // factor, y // factor) for x, y in points], fill=255)
    if factor != 1:
        result = result.resize((WIDTH, HEIGHT), Image.Resampling.NEAREST)
    return np.asarray(result) != 0


def rgba_mask(source, mask):
    result = source.copy()
    result[~mask] = 0
    return Image.fromarray(result, "RGBA")


def points_text(points):
    return "PackedVector2Array(" + ", ".join(str(n) for point in points for n in point) + ")"


def pack_cells(cells):
    # Godot4.5 TileMapLayer format0: version header plus signed16-bit cell/source/
    # atlas/alternative records; the same portable representation as floor01.
    return base64.b64encode(b"\x00\x00" + b"".join(
        struct.pack("<hhhhhh", x, y, 0, x, y, 0) for x, y in cells)).decode()


def terrain(name, image, sort_bases=None):
    image.save(OUT / f"{name}.png")
    alpha = np.asarray(image)[:, :, 3]
    cells, entries = [], []
    for y in range(HEIGHT // TILE):
        for x in range(WIDTH // TILE):
            if not alpha[y*TILE:(y+1)*TILE, x*TILE:(x+1)*TILE].any():
                continue
            cells.append((x, y))
            entries.append(f"{x}:{y}/0 = 0")
            if sort_bases is not None:
                bases = sort_bases[y*TILE:(y+1)*TILE, x*TILE:(x+1)*TILE]
                nonzero = bases[bases != 0]
                # A32px cell crossing adjacent bands belongs to the nearer base.
                foot = int(nonzero.max()) if nonzero.size else (y+1)*TILE
                entries.append(f"{x}:{y}/0/y_sort_origin = {foot-y*TILE-TILE//2}")
    resource = [
        '[gd_resource type="TileSet" load_steps=3 format=3]', "",
        f'[ext_resource type="Texture2D" path="res://Assets/Maps/BrackenMine/{name}.png" id="1"]', "",
        '[sub_resource type="TileSetAtlasSource" id="Atlas"]',
        'texture = ExtResource("1")', 'texture_region_size = Vector2i(32, 32)',
        *entries, "", '[resource]', 'tile_size = Vector2i(32, 32)',
        'sources/0 = SubResource("Atlas")', "",
    ]
    (OUT / f"{name}.tres").write_text("\n".join(resource), encoding="utf-8")
    return cells


def write_prop(prop, source, mask):
    ys, xs = np.nonzero(mask)
    left, top, right, bottom = int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1
    art = rgba_mask(source, mask).crop((left, top, right, bottom))
    art.save(OUT / "Props" / (prop["name"] + ".png"))
    anchor = prop["anchor"]
    parts = prop.get("collision_parts", [prop.get("collision")])
    lines = ['[gd_scene load_steps=2 format=3]', "",
             f'[ext_resource type="Texture2D" path="res://Assets/Maps/BrackenMine/Props/{prop["name"]}.png" id="1"]', "",
             f'[node name="{prop["name"]}" type="Node2D"]',
             'y_sort_enabled = true', 'texture_filter = 1',
             'metadata/source_family = "bracken-mine-approved"', "",
             '[node name="Footprint" type="StaticBody2D" parent="." groups=["map_object", "world_solid"]]',
             'collision_layer = 1', 'collision_mask = 0', "",
             '[node name="Visual" type="Sprite2D" parent="Footprint"]',
             f'position = Vector2({left-anchor[0]}, {top-anchor[1]})',
             'texture_filter = 1', 'texture = ExtResource("1")', 'centered = false', ""]
    for index, part in enumerate(parts):
        lines += [f'[node name="Base{index+1}" type="CollisionPolygon2D" parent="Footprint"]',
                  'polygon = ' + points_text([[x-anchor[0], y-anchor[1]] for x, y in part]), ""]
    (PROP_SCENES / (prop["name"] + ".tscn")).write_text("\n".join(lines), encoding="utf-8")
    return dict(name=prop["name"], source_rect=[left,top,right-left,bottom-top],
                world_anchor=anchor, local_anchor=[anchor[0]-left,anchor[1]-top],
                mask_polygons=prop.get("mask_polygons", [prop["polygon"]]), donor_offset=prop["donor_offset"],
                repaired_pixels=int(mask.sum()), collision_world=parts,
                scene=f'res://scenes/MapProps/BrackenMine/{prop["name"]}.tscn')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--prepare-pixel-base", action="store_true",
                        help="Rebuild the authorized crisp pixel export from the preserved approved master and PixelLab palette.")
    args = parser.parse_args()
    if args.prepare_pixel_base:
        master = Image.open(SOURCE.parent / "approved-base.png").convert("RGB")
        palette = Image.open(SOURCE.parent / "pixellab-native-grid.png").convert("RGB").quantize(
            colors=256, dither=Image.Dither.NONE)
        master.resize((WIDTH//2, HEIGHT//2), Image.Resampling.NEAREST).quantize(
            palette=palette, dither=Image.Dither.NONE).convert("RGBA").resize(
                (WIDTH, HEIGHT), Image.Resampling.NEAREST).save(SOURCE)
    if not SOURCE.is_file():
        raise SystemExit("Missing art_sources/bracken-mine/pixel-base.png; preserve the approved master and prepare the authorized same-geometry pixel source first.")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Props").mkdir(exist_ok=True)
    PROP_SCENES.mkdir(parents=True, exist_ok=True)
    source_image = Image.open(SOURCE).convert("RGBA")
    if source_image.size != (WIDTH, HEIGHT):
        raise SystemExit("The approved1536x1024 source must remain native size.")
    source = np.asarray(source_image).copy()
    layout = json.loads((OUT / "layout.json").read_text(encoding="utf-8"))
    floor = polygon_mask(layout["floor_boundary"])
    safe_donor_floor = floor.copy()
    for exclusion in layout["exclusions"]:
        safe_donor_floor &= ~polygon_mask(exclusion["polygon"])
    backing = source.copy()
    prop_masks = []
    prop_records = []
    used = np.zeros((HEIGHT,WIDTH), dtype=bool)
    for prop in PROPS:
        mask = np.zeros((HEIGHT, WIDTH), dtype=bool)
        for outline in prop.get("mask_polygons", [prop["polygon"]]):
            mask |= polygon_mask(outline, pixel_blocks=True)
        if np.any(mask & used):
            raise ValueError(f'Overlapping authored supply masks: {prop["name"]}')
        used |= mask
        prop_masks.append(mask)
        prop_records.append(write_prop(prop, source, mask))
        dx,dy = prop["donor_offset"]
        ys,xs = np.nonzero(mask)
        if not (np.all(xs+dx >= 0) and np.all(xs+dx < WIDTH) and np.all(ys+dy >= 0) and np.all(ys+dy < HEIGHT)):
            raise ValueError("Donor lies outside the approved image")
        if not np.all(safe_donor_floor[ys+dy, xs+dx]):
            raise ValueError(f'Hidden-floor donor crosses authored rock/water: {prop["name"]}')
        backing[ys,xs] = source[ys+dy,xs+dx]
    # Hand-authored geometry is a separation guide only. This tool neither emits
    # collision nor claims image colors determine the movement region.
    boundary = ~floor
    for exclusion in layout["exclusions"]:
        boundary |= polygon_mask(exclusion["polygon"])
    # Missing floor below the extracted assemblies is replaced only inside the
    # explicit silhouettes; the source cannot supply those hidden original pixels.
    boundary[used] = False
    front = np.zeros((HEIGHT,WIDTH), dtype=bool)
    sort_bases = np.zeros((HEIGHT,WIDTH), dtype=np.int16)
    for band in FOREGROUND:
        selected = polygon_mask(band["polygon"]) & boundary
        front |= selected
        if band["name"] == "CentralIsland":
            # The island's south base slopes by column. One global foot582
            # would incorrectly hide actors already south of either high tip.
            island = next(e for e in layout["exclusions"] if e["name"] == "CentralRockIsland")
            physical_base = polygon_mask(island["polygon"])
            for tile_x in range(0, WIDTH, TILE):
                ys, _ = np.nonzero(physical_base[:,tile_x:tile_x+TILE])
                foot_y = int(ys.max())+1 if ys.size else band["foot_y"]
                block = selected[:,tile_x:tile_x+TILE]
                sort_bases[:,tile_x:tile_x+TILE][block] = foot_y
        else:
            sort_bases[selected] = band["foot_y"]
    rear = boundary & ~front
    ground = ~boundary
    layers = {
        "Ground": rgba_mask(backing,ground),
        "BoundaryRock": rgba_mask(backing,rear),
        "Foreground": rgba_mask(backing,front),
    }
    cells = {name: terrain(name, art, sort_bases if name == "Foreground" else None)
             for name, art in layers.items()}
    scene = [f'[gd_scene load_steps={4+len(PROPS)} format=3]', ""]
    for index,name in enumerate(layers):
        scene += [f'[ext_resource type="TileSet" path="res://Assets/Maps/BrackenMine/{name}.tres" id="{index+1}"]']
    for index,prop in enumerate(PROPS):
        scene += [f'[ext_resource type="PackedScene" path="res://scenes/MapProps/BrackenMine/{prop["name"]}.tscn" id="{index+4}"]']
    scene += ["", '[node name="BrackenMineArtwork" type="Node2D"]', 'y_sort_enabled = true', 'texture_filter = 1',
              'metadata/native_size = Vector2i(1536, 1024)', 'metadata/world_pixels_per_source_pixel = 1.0', ""]
    for index,name in enumerate(layers):
        scene += [f'[node name="{name}" type="TileMapLayer" parent="."]']
        if name != "Foreground":
            scene += [f'z_index = {-20 if name == "Ground" else -10}']
        else:
            scene += ['y_sort_enabled = true']
        scene += ['texture_filter = 1', f'tile_map_data = PackedByteArray("{pack_cells(cells[name])}")',
                  f'tile_set = ExtResource("{index+1}")', ""]
    for index,prop in enumerate(PROPS):
        scene += [f'[node name="{prop["name"]}" parent="." instance=ExtResource("{index+4}")]',
                  f'position = Vector2({prop["anchor"][0]}, {prop["anchor"][1]})', ""]
    (PROJECT / "scenes/BrackenMineArtwork.tscn").write_text("\n".join(scene), encoding="utf-8")
    recomposed = Image.new("RGBA", source_image.size)
    for art in layers.values():
        recomposed.alpha_composite(art)
    for mask in prop_masks:
        recomposed.alpha_composite(rgba_mask(source,mask))
    diff = np.any(np.asarray(recomposed) != source, axis=2)
    hidden_changes = np.any(backing != source, axis=2)
    outside = hidden_changes & ~used
    if np.any(diff) or np.any(outside):
        raise AssertionError("Decomposition altered visible source pixels or repaired outside its authored masks")
    if args.preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        recomposed.save(args.preview)
    manifest = dict(schema=1, source="art_sources/bracken-mine/pixel-base.png",
        source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        native_size=[WIDTH,HEIGHT], world_pixels_per_source_pixel=1, tile_pixels=TILE,
        source_status="Approved layout with separately recorded deterministic pixel cleanup; original approved-base.png remains unchanged.",
        extraction_method="Authored binary2px silhouette polygons, native pixel copy; no color-key, resampling or image generation.",
        terrain_collision="None. layout.json and BrackenMineContent own authored terrain geometry.",
        layers={name:dict(atlas=f'{name}.png', tileset=f'{name}.tres', occupied_cells=len(value)) for name,value in cells.items()},
        foreground_bands=FOREGROUND, props=prop_records,
        wall_lanterns="Remain integral to continuous timber/stone support. A flat source does not contain complete standalone fixture backs or unobstructed support pixels.",
        exact_recomposition_changed_pixels=int(diff.sum()),
        hidden_floor_repaired_pixels=int(hidden_changes.sum()),
        pixels_repaired_outside_prop_masks=int(outside.sum()))
    json_write(OUT / "decomposition.json", manifest)
    print(f'BrackenMine:3 native32px terrain layers, {len(PROPS)} supply props; recomposition difference={int(diff.sum())}; hidden-floor repair={int(hidden_changes.sum())} pixels; outside-mask changes={int(outside.sum())}.')


if __name__ == "__main__":
    main()
