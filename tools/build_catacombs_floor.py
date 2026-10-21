"""Build editable floor-one tiles from the approved blueprint and existing native art.

Usage: python tools/build_catacombs_floor.py [--preview /outside/repo/preview.png]
Pillow and numpy are authoring dependencies, never game runtime dependencies.
No model call, network access, or absolute machine path is needed to rebuild.
"""
import argparse
import base64
import json
import math
from pathlib import Path
import struct

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_sources/golem-catacombs-floor01"
PROJECT = ROOT / "godot_client"
OUTPUT = PROJECT / "Assets/Maps/GolemCatacombs/Floor01"
KINGDOM = PROJECT / "Assets/Maps/GolemKingdom/Detail4x"
CELL = 24
TILE = 32
WIDTH, HEIGHT = 384, 300


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def in_polygon(x, y, polygon):
    inside = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > y) != (b[1] > y):
            if x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
                inside = not inside
    return inside


def segment_distance(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
    return math.hypot(x-a[0]-t*dx, y-a[1]-t*dy)


def floor_mask(blueprint):
    # Sample cell centres. Rounded polyline joins preserve the authored clear widths.
    mask = np.zeros((HEIGHT, WIDTH), dtype=bool)
    for cy in range(HEIGHT):
        for cx in range(WIDTH):
            x, y = (cx+.5)*CELL, (cy+.5)*CELL
            floor = any(in_polygon(x, y, r["points"]) for r in blueprint["rooms"])
            if not floor:
                floor = any(segment_distance(x, y, a, b) <= p["width"]/2
                            for p in blueprint["passages"]
                            for a, b in zip(p["points"], p["points"][1:]))
            # Keep only the northern gallery island. The two approved removals are floor.
            mask[cy, cx] = floor and not in_polygon(x, y, blueprint["islands"][0])
    return mask


def grow(mask, distance):
    result = mask.copy()
    for _ in range(distance):
        before = np.pad(result, 1)
        result = np.logical_or.reduce([before[y:y+HEIGHT, x:x+WIDTH]
                                      for y in range(3) for x in range(3)])
    return result


def periodic_ground(source, period=1024):
    """Wrap original native pixels through minimum-error overlap seams.

    The source canvas contains extra overlap pixels in each axis. Those
    are the continuation after the tile edge, not enlarged or blurred pixels.
    A constrained minimum cut hides the join inside the irregular mortar.
    """
    data = np.array(source.convert("RGBA"))
    h,w,_ = data.shape
    overlap_x, overlap_y = w-period, h-period
    assert min(overlap_x,overlap_y) >= 32

    def seam(error):
        rows,cols = error.shape
        middle = cols//2
        previous = np.zeros((rows,cols),dtype=np.int16)
        total = np.full(cols,np.inf)
        total[middle] = error[0,middle]
        for row in range(1,rows):
            choices = np.stack((np.r_[np.inf,total[:-1]],total,np.r_[total[1:],np.inf]))
            direction = np.argmin(choices,axis=0)-1
            previous[row] = np.arange(cols)+direction
            total = np.min(choices,axis=0)+error[row]
        result = np.empty(rows,dtype=np.int16)
        col = middle
        for row in range(rows-1,-1,-1):
            result[row] = col
            col = int(previous[row,col])
        return result

    horizontal = data[:,:period].copy()
    a,b = data[:,:overlap_x],data[:,period:]
    error = np.mean((a[:,:,:3].astype(float)-b[:,:,:3])**2,axis=2)
    cuts = seam(error)
    for y,x in enumerate(cuts):
        horizontal[y,:x] = b[y,:x]
    a,b = horizontal[:overlap_y],horizontal[period:]
    error = np.mean((a[:,:,:3].astype(float)-b[:,:,:3])**2,axis=2).T
    cuts = seam(error)
    result = horizontal[:period].copy()
    for x,y in enumerate(cuts):
        result[:y,x] = b[:y,x]
    return Image.fromarray(result)


def pack_cells(cells):
    return base64.b64encode(b"\x00\x00" + b"".join(
        struct.pack("<hhhhhh", x, y, 0, ax, ay, 0) for x, y, ax, ay in cells)).decode()


def tileset(name, image, size=32, collision=False, tall=False):
    image.save(OUTPUT / (name + ".png"))
    w, h = image.size
    tile_h = 96 if tall else size
    entries = []
    for y in range(h//tile_h):
        for x in range(w//size):
            entries.append(f"{x}:{y}/0 = 0")
            if tall:
                entries += [f"{x}:{y}/0/texture_origin = Vector2i(0, -32)",
                            f"{x}:{y}/0/y_sort_origin = 16"]
            if collision:
                entries += [f"{x}:{y}/0/physics_layer_0/polygon_0/points = PackedVector2Array(-16, -16, 16, -16, 16, 16, -16, 16)"]
    text = ('[gd_resource type="TileSet" load_steps=3 format=3]\n\n'
            f'[ext_resource type="Texture2D" path="res://Assets/Maps/GolemCatacombs/Floor01/{name}.png" id="1"]\n\n'
            '[sub_resource type="TileSetAtlasSource" id="Atlas"]\n'
            f'texture = ExtResource("1")\ntexture_region_size = Vector2i({size}, {tile_h})\n'
            + "\n".join(entries) + '\n\n[resource]\ntile_size = Vector2i(32, 32)\n')
    if collision:
        text += 'physics_layer_0/collision_layer = 1\nphysics_layer_0/collision_mask = 0\n'
    text += 'sources/0 = SubResource("Atlas")\n'
    (OUTPUT / (name + ".tres")).write_text(text, encoding="utf-8")


def wall_atlas():
    # The installed north rail has a straight native stone cap and front face.
    # Stack its source masonry courses; no oversized overview pixels are used.
    source = Image.open(KINGDOM / "Objects/north-approach-low-rail.png").convert("RGBA")
    atlas = Image.new("RGBA", (32*8, 96))
    for variant in range(8):
        x = 20 + variant*27
        tile = Image.new("RGBA", (32, 96), (0, 0, 0, 0))
        for row in range(4):
            sx = 20 + ((variant*27+row*43) % 200)
            face = source.crop((sx, 18, sx+32, 35))
            tile.paste(face, (0, 25+row*17))
        tile.paste(source.crop((x, 6, x+32, 24)), (0, 7))
        # Base contact shadow stays inside the blocked cell footprint.
        ImageDraw.Draw(tile).line((0, 94, 31, 94), fill=(27, 25, 28, 255), width=2)
        atlas.paste(tile, (variant*32, 0))
    return atlas


def cleaned_overview():
    original = Image.open(SOURCE / "overview-approved.png").convert("RGBA")
    repair = Image.open(SOURCE / "pillar-removal-raw.png").convert("RGBA")
    assert original.size == repair.size == (1422, 1106)
    # Soft margins are confined to clear floor around the two requested objects.
    masks = Image.new("L", original.size)
    draw = ImageDraw.Draw(masks)
    draw.polygon([(1020,496),(1082,473),(1147,497),(1173,555),(1140,606),(1069,615),(1026,573)], fill=255)
    draw.polygon([(803,625),(839,594),(892,603),(923,648),(901,705),(841,720),(803,681)], fill=255)
    # Keep full opacity in the removed footprints; feather only the outer six pixels.
    from PIL import ImageFilter
    masks = masks.filter(ImageFilter.GaussianBlur(3))
    combined = Image.composite(repair, original, masks)
    combined.save(SOURCE / "overview-pillars-removed.png")
    a, b, m = np.array(original), np.array(combined), np.array(masks)
    assert np.array_equal(a[m == 0], b[m == 0])
    return {"size": list(original.size), "unmasked_pixels_changed": 0,
            "changed_pixels": int(np.any(a != b, axis=2).sum())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    blueprint = json.loads((SOURCE / "blueprint.json").read_text(encoding="utf-8"))
    mask = floor_mask(blueprint)
    boundary = grow(mask, 1) & ~mask
    rock_band = grow(mask, 7) & ~mask
    navigable = mask.copy()
    # Physical bases of the two exit gateway posts. Ground continues underneath
    # them, but navigation excludes exactly the same 24-world-pixel cells.
    prop_bases = [(1440,6768,48,48),(1632,6768,48,48)]
    for x,y,w,h in prop_bases:
        navigable[y//CELL:(y+h)//CELL,x//CELL:(x+w)//CELL] = False
    rock_source = Image.open(KINGDOM / "Terrain/CavernRock.png")
    # Source crops exclude repaired underpainting, props, walls and stairs.
    floor_path = SOURCE / "cobble-ground.png"
    assert floor_path.exists(), "Missing generated native paving source; see art_sources provenance"
    raw_floor = Image.open(floor_path)
    assert raw_floor.size == (1254,1254), "Source dimensions changed; review cobble scale before exporting"
    # The generated stones were twice the requested diameter. Reduce by exactly
    # two with nearest sampling, preserving hard clusters, then close the edges.
    floor = periodic_ground(raw_floor.resize((627,627),Image.Resampling.NEAREST),512)
    assert floor.size == (512,512)
    rough = Image.new("RGBA", (32,32))
    # Retain the native basalt orientation, avoiding mirrored column silhouettes.
    rock = rock_source.crop((4736,448,4992,704)).convert("RGBA")
    wall = wall_atlas()
    tileset("Ground", floor)
    tileset("FloorDetails", rough)
    tileset("VolcanicRock", rock)
    tileset("Walls", wall, collision=True, tall=True)

    cells = {name: [] for name in ("Ground", "FloorDetails", "VolcanicRock", "Walls")}
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if mask[y, x]:
                cells["Ground"].append((x, y, x % 16, y % 16))
            elif rock_band[y, x]:
                cells["VolcanicRock"].append((x, y, x % 8, y % 8))
            if boundary[y, x]:
                cells["Walls"].append((x, y, (x*3+y*5) % 8, 0))
    layout = {"version": 1, "world_size": [WIDTH*CELL, HEIGHT*CELL],
              "cell_world": CELL, "width_cells": WIDTH, "height_cells": HEIGHT,
              "native_art_cell": TILE, "content_scale": .75,
              "entry": blueprint["entry"], "descent": blueprint["descent"],
              "rooms": blueprint["rooms"], "passages": blueprint["passages"],
              "room_waypoints": {r["name"]: r["probe"] for r in blueprint["rooms"]},
              "removed_island_waypoints": [[5550,4290],[6980,3530]],
              "retained_island": blueprint["islands"][0],
              "solid_prop_bounds": prop_bases,
              "walkable_cells": [[int(x),int(y)] for y,x in np.argwhere(navigable)],
              "blocked_boundary_cells": [[int(x),int(y)] for y,x in np.argwhere(boundary)]}
    write_json(OUTPUT / "layout.json", layout)

    ext = [f'[ext_resource type="TileSet" path="res://Assets/Maps/GolemCatacombs/Floor01/{name}.tres" id="{i+1}"]'
           for i,name in enumerate(cells)]
    reusable = ["brazier-armory-inner", "brazier-temple-west-wall", "southern-exit-stairs", "southwest-corridor-north-gateway"]
    ext += [f'[ext_resource type="Texture2D" path="res://Assets/Maps/GolemKingdom/Detail4x/Objects/{name}.png" id="{i+5}"]'
            for i,name in enumerate(reusable)]
    ext += ['[ext_resource type="Material" path="res://Assets/Maps/GolemKingdom/Rendering/CrispEnvironment.tres" id="9"]']
    scene = '[gd_scene load_steps=10 format=4]\n\n' + "\n".join(ext)
    scene += '\n\n[node name="CatacombsFloor01Content" type="Node2D"]\nscale = Vector2(0.75, 0.75)\ny_sort_enabled = true\ntexture_filter = 1\n'
    for i, (name, data) in enumerate(cells.items()):
        scene += f'\n[node name="{name}" type="TileMapLayer" parent="."]\n'
        scene += 'material = ExtResource("9")\n'
        if name == "Walls":
            scene += 'y_sort_enabled = true\ny_sort_origin = 16\n'
        else:
            scene += f'z_index = {-30+i}\n'
        scene += f'tile_map_data = PackedByteArray("{pack_cells(data)}")\ntile_set = ExtResource("{i+1}")\n'
    scene += '\n[node name="Props" type="Node2D" parent="."]\ny_sort_enabled = true\n'
    # Sparse lighting/decor lives behind the same physical rock edge, preserving
    # every clear corridor and the two deliberately cleared central locations.
    braziers = []
    for room in blueprint["rooms"]:
        px, py = room["probe"]
        nearby = [(x,y) for x,y,_,_ in cells["Walls"]
                  if y+2 < HEIGHT and mask[y+1,x]
                  and abs((x+.5)*CELL-px) < 1000 and abs((y+.5)*CELL-py) < 900]
        for x,y in sorted(nearby, key=lambda p: (p[0]*71+p[1]*37)%193):
            position = ((x+.5)*CELL,(y+.5)*CELL)
            if all(math.dist(position,old) > 500 for old in braziers):
                braziers.append(position)
                if len([p for p in braziers if math.dist(p,(px,py)) < 1400]) >= 3:
                    break
    for i,(x,y) in enumerate(braziers):
        resource = 5+i%2
        foot_x,foot_y = (68,136) if resource == 5 else (52,120)
        scene += (f'\n[node name="Brazier{i+1:02}" type="Node2D" parent="Props"]\n'
                  f'position = Vector2({x/.75:g}, {y/.75:g})\n'
                  f'\n[node name="Artwork" type="Sprite2D" parent="Props/Brazier{i+1:02}"]\n'
                  f'material = ExtResource("9")\nposition = Vector2({-foot_x}, {-foot_y})\ncentered = false\ntexture = ExtResource("{resource}")\n')
    # The stair is a ground-plane object. The visible gateway lines up exactly
    # with the deliberately clicked floor exit at world (1550,6800).
    scene += ('\n[node name="KingdomExitStairs" type="Sprite2D" parent="Props"]\n'
              'position = Vector2(2066.667, 9030)\nz_index = -20\ntexture = ExtResource("7")\n'
              '\n[node name="KingdomExitGateway" type="Sprite2D" parent="Props"]\n'
              'position = Vector2(2066.667, 9066.667)\noffset = Vector2(0, -85)\ntexture = ExtResource("8")\n'
              '\n[node name="DescentStairs" type="Sprite2D" parent="Props"]\n'
              'position = Vector2(10946.667, 520)\nz_index = -20\ntexture = ExtResource("7")\n'
              '\n[node name="HotSeams" type="Node2D" parent="."]\nz_index = -27\n')
    scene += '\n[node name="PropFootprints" type="StaticBody2D" parent="."]\ncollision_layer = 1\ncollision_mask = 0\n'
    for i,(x,y,w,h) in enumerate(prop_bases):
        points = [(x/.75,y/.75),((x+w)/.75,y/.75),((x+w)/.75,(y+h)/.75),(x/.75,(y+h)/.75)]
        flat = ", ".join(f"{v:g}" for p in points for v in p)
        scene += (f'\n[node name="GatewayPost{i+1}" type="CollisionPolygon2D" parent="PropFootprints"]\n'
                  f'polygon = PackedVector2Array({flat})\n')
    (PROJECT / "scenes/CatacombsFloor01Content.tscn").write_text(scene, encoding="utf-8")
    report = cleaned_overview()
    write_json(OUTPUT / "manifest.json", {
        "status": "installed", "environment_only": True,
        "source": "art_sources/golem-catacombs-floor01/blueprint.json",
        "source_overview": "art_sources/golem-catacombs-floor01/overview-pillars-removed.png",
        "world_size": layout["world_size"], "native_world_pixels_per_art_pixel": .75,
        "layer_cells": {name: len(data) for name,data in cells.items()},
        "overview_local_edit": report,
        "reused_sources": {
            "Ground": {"file": "art_sources/golem-catacombs-floor01/cobble-ground.png", "method": "exact half-size nearest reduction, then627 to512 periodic overlap minimum-cut; no enlargement or blur"},
            "FloorDetails": {"method": "empty paintable detail layer, reserved for local decals"},
            "VolcanicRock": {"file": "GolemKingdom/Detail4x/Terrain/CavernRock.png", "rect": [4736,448,256,256]},
            "Walls": {"file": "GolemKingdom/Detail4x/Objects/north-approach-low-rail.png"}},
        "build_script": "tools/build_catacombs_floor.py",
        "limitations": ["Overview is an art reference; native modular assembly preserves the room graph and scale, not every overview pixel.",
                         "Floor two and three are not installed. Northeast descent is sealed."]})
    if args.preview:
        preview = Image.new("RGBA", (WIDTH*4, HEIGHT*4), (16,21,27,255))
        layers = {"Ground":floor,"FloorDetails":rough,"VolcanicRock":rock,"Walls":wall}
        for name, data in cells.items():
            atlas = layers[name]
            for x,y,ax,ay in data:
                h = 96 if name == "Walls" else 32
                patch = atlas.crop((ax*32,ay*h,(ax+1)*32,(ay+1)*h))
                patch = patch.resize((4,12 if h == 96 else 4), Image.Resampling.LANCZOS)
                preview.alpha_composite(patch, (x*4,y*4-(8 if h == 96 else 0)))
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        preview.convert("RGB").save(args.preview)
    print(json.dumps({"layers": {k:len(v) for k,v in cells.items()}, "overview_edit":report}))


if __name__ == "__main__":
    main()
