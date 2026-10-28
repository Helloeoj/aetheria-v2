"""Authored Valtherian floor geometry and conservative ore-placement analysis.

No image is resized or edited. Placement output is a proposal for the actual
Godot content/physics checks, never an automatic worldbuilding certificate.
"""
from __future__ import annotations

from collections import defaultdict
from pathlib import Path
import math
import re

import numpy as np
from PIL import Image

CELL = 32
ANCHOR = (48, 72)
MAX_NUDGE = 64
SCENES = {
    "blackstone": "BlackstoneFull.tscn", "coal": "CoalFull.tscn",
    "mithril": "MithrilOreFull.tscn", "adamantite": "AdamantiteOreFull.tscn",
    "iron": "IronOreFull.tscn", "copper": "CopperOreFull.tscn",
    "tin": "TinOreFull.tscn", "silver": "SilverOreFull.tscn",
    "gold": "GoldOreFull.tscn", "runite": "RuniteOreFull.tscn",
}


def build_floor(contract: dict) -> set[tuple[int, int]]:
    """Reconstruct the approved cell union, including its chipped-edge allowance."""
    if contract.get("gameplay_cell_pixels", CELL) != CELL:
        raise ValueError("Valtherian movement cells must remain 32 world pixels")
    world_columns, world_rows = contract["world_size_cells"]
    cells: set[tuple[int, int]] = set()

    def rectangle(x0, y0, x1, y1):
        cells.update((x, y) for y in range(max(0, y0), min(world_rows, y1))
                     for x in range(max(0, x0), min(world_columns, x1)))

    def corridor(points, span):
        if span <= 0 or span % 2:
            raise ValueError("Authored corridor widths must be positive even cell counts")
        half = span // 2
        for a, b in zip(points, points[1:]):
            if a[0] != b[0] and a[1] != b[1]:
                raise ValueError("Authored corridor segments must be cardinal")
            rectangle(min(a[0], b[0])-half, min(a[1], b[1])-half,
                      max(a[0], b[0])+half, max(a[1], b[1])+half)

    corridor(contract["main_route_cells"], contract["main_width_cells"])
    for branch in contract["branches"]:
        corridor(branch["points"], contract["side_width_cells"])
    for room in contract["rooms"]:
        x, y, width, height = room["clear_rect_cells"]
        rectangle(x, y, x+width, y+height)
        rectangle(x-1, y, x+width+1, y+height)
        rectangle(x, y-1, x+width, y+height+1)
    return cells


def floor_polygons(cells: set[tuple[int, int]]) -> list[list[list[int]]]:
    """Trace simple world-space boundary rings, without repeating closing points.

    In screen coordinates outer rings have positive signed area and holes have
    negative area. Diagonally touching components retain separate rings.
    """
    edges = set()
    for x, y in cells:
        if (x, y-1) not in cells:
            edges.add(((x,y), (x+1,y)))
        if (x+1, y) not in cells:
            edges.add(((x+1,y), (x+1,y+1)))
        if (x, y+1) not in cells:
            edges.add(((x+1,y+1), (x,y+1)))
        if (x-1, y) not in cells:
            edges.add(((x,y+1), (x,y)))
    outgoing = defaultdict(set)
    for start, end in edges:
        outgoing[start].add(end)
    directions = {(1,0): 0, (0,1): 1, (-1,0): 2, (0,-1): 3}
    turn_priority = {1: 0, 0: 1, 3: 2, 2: 3}
    rings = []
    while edges:
        first, following = min(edges)
        ring = [first]
        previous, current = first, following
        edges.remove((previous, current))
        outgoing[previous].remove(current)
        while current != first:
            ring.append(current)
            incoming = directions[(current[0]-previous[0], current[1]-previous[1])]
            choices = outgoing[current]
            if not choices:
                raise ValueError("The authored floor boundary is not closed")

            def turn(candidate):
                direction = directions[(candidate[0]-current[0], candidate[1]-current[1])]
                return turn_priority[(direction-incoming) % 4], candidate

            following = min(choices, key=turn)
            edges.remove((current, following))
            outgoing[current].remove(following)
            previous, current = current, following
        corners = [point for i, point in enumerate(ring)
                   if not (ring[i-1][0] == point[0] == ring[(i+1) % len(ring)][0]
                           or ring[i-1][1] == point[1] == ring[(i+1) % len(ring)][1])]
        rings.append([[x*CELL, y*CELL] for x, y in corners])

    def signed_area(ring):
        return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(ring, ring[1:]+ring[:1])) / 2

    return sorted(rings, key=lambda ring: (-abs(signed_area(ring)), min(map(tuple, ring))))


def merged_void_rects(cells: set[tuple[int, int]], size=(192, 104)) -> list[list[int]]:
    """Return nonoverlapping world rectangles covering exactly the bounded void."""
    width, height = size
    active = {}
    rectangles = []
    for y in range(height+1):
        runs = set()
        if y < height:
            x = 0
            while x < width:
                if (x, y) in cells:
                    x += 1
                    continue
                start = x
                while x < width and (x, y) not in cells:
                    x += 1
                runs.add((start, x-start))
        for run in list(active):
            if run not in runs:
                start_y = active.pop(run)
                rectangles.append([run[0]*CELL, start_y*CELL, run[1]*CELL, (y-start_y)*CELL])
        for run in runs:
            active.setdefault(run, y)
    return sorted(rectangles, key=lambda rectangle: (rectangle[1], rectangle[0], rectangle[2], rectangle[3]))


def _dilate(mask: np.ndarray, radius: int, outside=False) -> np.ndarray:
    """Integer Euclidean disk dilation; no rectangular bounding-box substitute."""
    result = mask.copy()
    height, width = mask.shape
    for dy in range(-radius, radius+1):
        for dx in range(-radius, radius+1):
            if dx*dx+dy*dy > radius*radius:
                continue
            x0, x1 = max(0, dx), min(width, width+dx)
            y0, y1 = max(0, dy), min(height, height+dy)
            result[y0:y1, x0:x1] |= mask[y0-dy:y1-dy, x0-dx:x1-dx]
    if outside:
        result[:radius, :] = True
        result[-radius:, :] = True
        result[:, :radius] = True
        result[:, -radius:] = True
    return result


def _asset(marker: dict, repo: Path) -> dict:
    ore = marker["ore"]
    expected = "res://scenes/MapProps/OreNodes/" + SCENES[ore]
    scene = marker.get("canonical_native_scene", expected)
    if scene != expected:
        raise ValueError(f"{marker['id']}: expected existing canonical {ore} scene")
    text = (repo / "godot_client" / scene.removeprefix("res://")).read_text(encoding="utf-8")
    for section in re.split(r"(?=^\[node )", text, flags=re.MULTILINE)[1:]:
        header, _, attributes = section.partition("\n")
        position = re.search(r"^position = Vector2\(([^)]+)\)", attributes, flags=re.MULTILINE)
        scale = re.search(r"^scale = Vector2\(([^)]+)\)", attributes, flags=re.MULTILINE)
        if scale and tuple(float(value.strip()) for value in scale[1].split(",")) != (1, 1):
            raise ValueError(f"{scene}: unexpected transformed canonical node; use the actual-scene validator")
        coordinates = tuple(float(value.strip()) for value in position[1].split(",")) if position else (0, 0)
        if 'type="Sprite2D"' in header:
            if coordinates != (-48, -72) or "centered = false" not in attributes:
                raise ValueError(f"{scene}: canonical source anchor changed")
        elif coordinates != (0, 0):
            raise ValueError(f"{scene}: unexpected canonical base transform")
    textures = re.findall(r'\[ext_resource type="Texture2D" path="([^"]+)"', text)
    if len(textures) != 1:
        raise ValueError(f"{scene}: expected one standalone canonical texture")
    texture = textures[0]
    with Image.open(repo / "godot_client" / texture.removeprefix("res://")) as image:
        if image.size != (96, 96):
            raise ValueError(f"{texture}: canonical native canvas changed")
        alpha = np.array(image.convert("RGBA"))[:, :, 3] > 0
    ys, xs = np.nonzero(alpha)
    if not len(xs):
        raise ValueError(f"{texture}: empty canonical silhouette")
    polygons = []
    for specification in re.findall(r"polygon = PackedVector2Array\(([^)]+)\)", text):
        numbers = [float(value.strip()) for value in specification.split(",")]
        if len(numbers) < 6 or len(numbers) % 2:
            raise ValueError(f"{scene}: invalid canonical base polygon")
        polygons.append(list(zip(numbers[::2], numbers[1::2])))
    if len(polygons) != 2:
        raise ValueError(f"{scene}: expected both canonical rock bases")
    return {"scene": scene, "texture": texture, "alpha": alpha, "xs": xs,
            "ys": ys, "dilated": _dilate(alpha, 4), "polygons": polygons}


def _peer_overlap(a: dict, root_a: tuple[int, int], b: dict, root_b: tuple[int, int]) -> bool:
    xs = a["xs"] + root_a[0] - root_b[0]
    ys = a["ys"] + root_a[1] - root_b[1]
    valid = (xs >= 0) & (xs < 96) & (ys >= 0) & (ys < 96)
    return bool(b["dilated"][ys[valid], xs[valid]].any())


def _box_overlaps_polygon(center, polygon) -> bool:
    """Convex SAT with contact conservatively treated as collision."""
    x, y = center
    rectangle = [(x-12,y-12), (x+12,y-12), (x+12,y+12), (x-12,y+12)]
    axes = [(1,0), (0,1)]
    axes += [(-(b[1]-a[1]), b[0]-a[0]) for a,b in zip(polygon, polygon[1:]+polygon[:1])]
    for ax, ay in axes:
        if ax == ay == 0:
            continue
        box_projection = [px*ax+py*ay for px,py in rectangle]
        polygon_projection = [px*ax+py*ay for px,py in polygon]
        if max(box_projection) < min(polygon_projection)-1e-8 or max(polygon_projection) < min(box_projection)-1e-8:
            return False
    return True


def _approaches(root, floor, world_polygons):
    height, width = floor.shape
    candidates = []
    for cell_y in range(math.ceil((root[1]-80-16)/CELL), math.floor((root[1]+80-16)/CELL)+1):
        for cell_x in range(math.ceil((root[0]-80-16)/CELL), math.floor((root[0]+80-16)/CELL)+1):
            x, y = cell_x*CELL+16, cell_y*CELL+16
            squared = (x-root[0])**2+(y-root[1])**2
            if squared > 80**2 or x-12 < 0 or y-12 < 0 or x+12 > width or y+12 > height:
                continue
            if not floor[y-12:y+12, x-12:x+12].all():
                continue
            if any(_box_overlaps_polygon((x,y), polygon) for polygon in world_polygons):
                continue
            candidates.append({"world_xy": [x,y], "distance_to_root": round(math.sqrt(squared), 6),
                               "front": y-root[1] >= 16})
    return sorted(candidates, key=lambda point: (not point["front"], point["distance_to_root"],
                                               abs(point["world_xy"][0]-root[0]), point["world_xy"][1], point["world_xy"][0]))


def place_ores(markersdict: dict, repo_root, cells: set[tuple[int, int]], wall_mask_path=None) -> list[dict]:
    """Preserve valid marks and minimally nudge only genuine silhouette conflicts.

    Floor/wall clearance is 2px and peer clearance 4px, evaluated on actual
    opaque pixels. Repairs are ordered by integer Euclidean displacement and
    fail beyond 64px. All originally valid targets are reserved before repairs.
    Approach candidates fit the 24px actor against floor and actual canonical
    convex bases; reachability and swept travel still require the Godot gate.
    """
    if not cells:
        raise ValueError("Cannot place ore without authored floor")
    if any(x < 0 or y < 0 for x,y in cells):
        raise ValueError("The Valtherian plan uses a nonnegative fixed origin")
    markers = markersdict["markers"]
    if len({marker["id"] for marker in markers}) != len(markers):
        raise ValueError("Marker identifiers must be unique")
    if markersdict.get("total_markers", len(markers)) != len(markers):
        raise ValueError("Marker count does not match its source record")
    width, height = (max(point[axis] for point in cells)+1 for axis in (0,1))
    width, height = width*CELL, height*CELL
    wall = None
    if wall_mask_path is not None:
        with Image.open(wall_mask_path) as image:
            if image.width < width or image.height < height:
                raise ValueError("Wall mask does not cover the authored floor extent")
            wall = np.array(image.convert("L")) > 0
        height, width = wall.shape
    floor = np.zeros((height, width), dtype=bool)
    for x, y in cells:
        floor[y*CELL:(y+1)*CELL, x*CELL:(x+1)*CELL] = True
    floor_bad = _dilate(~floor, 2, outside=True)
    wall_bad = _dilate(wall, 2) if wall is not None else None
    occupied = np.zeros_like(floor)
    repo = Path(repo_root)
    assets = {}
    entries = []
    for marker in markers:
        expected_scene = "res://scenes/MapProps/OreNodes/" + SCENES[marker["ore"]]
        if marker.get("canonical_native_scene", expected_scene) != expected_scene:
            raise ValueError(f"{marker['id']}: canonical scene disagrees with ore identity")
        if marker["ore"] not in assets:
            assets[marker["ore"]] = _asset(marker, repo)
        asset = assets[marker["ore"]]
        center = marker["planned_visible_center_world_xy"]
        target = (round(center[0]), round(center[1]+24))
        if "canonical_root_nearest_integer_world_xy" in marker and tuple(marker["canonical_root_nearest_integer_world_xy"]) != target:
            raise ValueError(f"{marker['id']}: marker root disagrees with its visible center")
        entries.append({"marker": marker, "asset": asset, "target": target})

    def conflicts(entry, root, peers, details=False):
        asset = entry["asset"]
        xs, ys = asset["xs"]+root[0]-48, asset["ys"]+root[1]-72
        if xs.min() < 0 or ys.min() < 0 or xs.max() >= width or ys.max() >= height:
            return ["floor_or_bounds"]
        reasons = []
        if floor_bad[ys,xs].any():
            reasons.append("floor_clearance_2px")
        if wall_bad is not None and wall_bad[ys,xs].any():
            reasons.append("wall_art_clearance_2px")
        if peers and occupied[ys,xs].any():
            if details:
                reasons += ["peer_clearance_4px:"+peer["marker"]["id"] for peer in peers
                            if _peer_overlap(asset, root, peer["asset"], peer["root"])]
            else:
                reasons.append("peer_clearance_4px")
        return reasons

    def reserve(entry, root):
        entry["root"] = root
        ys, xs = np.nonzero(entry["asset"]["dilated"])
        xs, ys = xs+root[0]-48, ys+root[1]-72
        valid = (xs >= 0) & (xs < width) & (ys >= 0) & (ys < height)
        occupied[ys[valid],xs[valid]] = True

    for entry in entries:
        entry["initial_conflicts"] = conflicts(entry, entry["target"], [])
    for index, entry in enumerate(entries):
        for peer in entries[index+1:]:
            if _peer_overlap(entry["asset"], entry["target"], peer["asset"], peer["target"]):
                entry["initial_conflicts"].append("peer_clearance_4px:"+peer["marker"]["id"])
                peer["initial_conflicts"].append("peer_clearance_4px:"+entry["marker"]["id"])
    placed = []
    for entry in entries:
        if not entry["initial_conflicts"]:
            reserve(entry, entry["target"])
            entry["target_conflicts_when_placed"] = []
            placed.append(entry)
    offsets = sorted(((dx,dy) for dy in range(-MAX_NUDGE,MAX_NUDGE+1)
                      for dx in range(-MAX_NUDGE,MAX_NUDGE+1)
                      if dx*dx+dy*dy <= MAX_NUDGE*MAX_NUDGE),
                     key=lambda point: (point[0]**2+point[1]**2, abs(point[0]), abs(point[1]), point[1], point[0]))
    for entry in entries:
        if "root" in entry:
            continue
        entry["target_conflicts_when_placed"] = conflicts(entry, entry["target"], placed, details=True)
        for dx, dy in offsets:
            root = (entry["target"][0]+dx, entry["target"][1]+dy)
            if not conflicts(entry, root, placed):
                reserve(entry, root)
                placed.append(entry)
                break
        else:
            raise ValueError(f"{entry['marker']['id']}: no conflict-free integer correction within 64px; target={entry['target']}, reasons={entry['target_conflicts_when_placed']}")
    world_polygons = [[(root[0]+x, root[1]+y) for x,y in polygon]
                      for entry in entries for root in [entry["root"]]
                      for polygon in entry["asset"]["polygons"]]
    results = []
    for entry in entries:
        marker, asset, root, target = entry["marker"], entry["asset"], entry["root"], entry["target"]
        approaches = _approaches(root, floor, world_polygons)
        if not approaches:
            raise ValueError(f"{marker['id']}: no grid approach within 80px fits the 24px actor and canonical bases")
        dx, dy = root[0]-target[0], root[1]-target[1]
        results.append({"id": marker["id"], "ore": marker["ore"], "room_id": marker.get("room_id"),
                        "scene": asset["scene"], "texture": asset["texture"],
                        "requested_visible_center_world_xy": list(marker["planned_visible_center_world_xy"]),
                        "rounded_target_root_world_xy": list(target), "root_world_xy": list(root),
                        "visible_center_world_xy": [root[0],root[1]-24], "delta_world_xy": [dx,dy],
                        "moved": root != target, "displacement_world_pixels": round(math.hypot(dx,dy),6),
                        "initial_conflicts": entry["initial_conflicts"],
                        "correction_reasons": entry["target_conflicts_when_placed"],
                        "wall_art_checked": wall is not None, "native_size": [96,96], "anchor": [48,72],
                        "world_pixels_per_source_pixel": 1,
                        "approach_candidates": approaches, "approach_world_xy": approaches[0]["world_xy"],
                        "approach_status": "Ranked floor/base-clear grid candidates only; actual Godot reachability and swept steps remain required"})
    return results
