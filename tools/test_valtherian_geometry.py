"""Focused invariants for authored floor topology and protected ore targets."""
from pathlib import Path
from collections import deque
import importlib.util
import json
import math
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODULE = Path(__file__).with_name("valtherian_geometry.py")
if MODULE.exists():
    spec = importlib.util.spec_from_file_location("valtherian_geometry", MODULE)
    geometry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(geometry)
else:
    geometry = None


def marker(name, x, y):
    return {"id": name, "ore": "iron", "room_id": "test-room",
            "planned_visible_center_world_xy": [x, y],
            "canonical_root_nearest_integer_world_xy": [round(x), round(y + 24)],
            "canonical_native_scene": "res://scenes/MapProps/OreNodes/IronOreFull.tscn"}


def signed_area(ring):
    return sum(a[0] * b[1] - b[0] * a[1]
               for a, b in zip(ring, ring[1:] + ring[:1])) / 2


class GeometryTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(geometry, "The scoped geometry helper is not implemented")

    def test_real_floor_has_all_5498_connected_cells(self):
        contract = json.loads((ROOT / "art_sources/valtherian-mines/planning/tile-layout-v3.json").read_text())
        cells = geometry.build_floor(contract)
        self.assertEqual(len(cells), 5498)
        self.assertEqual(sum(signed_area(ring) for ring in geometry.floor_polygons(cells)), 5498 * 32 * 32)
        reached = {(190, 64)}
        pending = deque(reached)
        while pending:
            x, y = pending.popleft()
            for point in ((x-1,y), (x+1,y), (x,y-1), (x,y+1)):
                if point in cells and point not in reached:
                    reached.add(point)
                    pending.append(point)
        self.assertEqual(reached, cells)
        self.assertIn((16, 24), reached)

    def test_floor_rings_and_void_rectangles_conserve_area_with_a_hole(self):
        cells = {(x,y) for x in range(3) for y in range(3)} - {(1,1)}
        rings = geometry.floor_polygons(cells)
        self.assertEqual(len(rings), 2)
        self.assertEqual(sum(signed_area(ring) for ring in rings), 8 * 32 * 32)
        self.assertTrue(any(signed_area(ring) < 0 for ring in rings))
        covered = set()
        for x, y, width, height in geometry.merged_void_rects(cells, (4,4)):
            rectangle = {(cx,cy) for cx in range(x//32, (x+width)//32)
                         for cy in range(y//32, (y+height)//32)}
            self.assertFalse(covered & rectangle)
            covered |= rectangle
        self.assertEqual(covered, {(x,y) for x in range(4) for y in range(4)} - cells)

    def test_diagonal_floor_contact_keeps_separate_simple_rings(self):
        rings = geometry.floor_polygons({(0,0), (1,1)})
        self.assertEqual(len(rings), 2)
        self.assertTrue(all(len(ring) == 4 for ring in rings))

    def test_unconflicted_target_is_exact_and_approaches_are_grid_centers(self):
        cells = {(x,y) for x in range(10) for y in range(10)}
        placed = geometry.place_ores({"markers": [marker("iron-01",160,160)]}, ROOT, cells)
        self.assertEqual(placed[0]["root_world_xy"], [160,184])
        self.assertFalse(placed[0]["moved"])
        self.assertTrue(placed[0]["approach_candidates"])
        for approach in placed[0]["approach_candidates"]:
            x, y = approach["world_xy"]
            self.assertEqual((x-16) % 32, 0)
            self.assertEqual((y-16) % 32, 0)
            self.assertLessEqual(math.dist((x,y), (160,184)), 80)

    def test_wall_conflict_uses_the_smallest_integer_displacement(self):
        cells = {(x,y) for x in range(10) for y in range(10)}
        with Image.open(ROOT / "godot_client/Assets/MapTiles/OreNodes/iron-ore-full-south.png") as source:
            alpha = source.getchannel("A")
            opaque = [(x-48,y-72) for y in range(96) for x in range(96) if alpha.getpixel((x,y))]
        wall = min(opaque, key=lambda point: (point[1], point[0]))
        wall = (wall[0]+160, wall[1]+184)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "wall-mask.png"
            mask = Image.new("L", (320,320))
            mask.putpixel(wall, 255)
            mask.save(path)
            placed = geometry.place_ores({"markers": [marker("iron-01",160,160)]}, ROOT, cells, path)[0]
        self.assertTrue(placed["moved"])
        dx, dy = placed["delta_world_xy"]
        best_squared = dx*dx + dy*dy
        for sx in range(-8,9):
            for sy in range(-8,9):
                if sx*sx + sy*sy >= best_squared:
                    continue
                nearest = min((160+ox+sx-wall[0])**2 + (184+oy+sy-wall[1])**2 for ox,oy in opaque)
                self.assertLessEqual(nearest, 4, "A shorter valid displacement was skipped")

    def test_repair_cannot_displace_an_originally_valid_later_target(self):
        cells = {(x,y) for x in range(10) for y in range(10)}
        placed = geometry.place_ores({"markers": [marker("iron-01",16,160), marker("iron-02",80,160)]}, ROOT, cells)
        self.assertEqual(placed[1]["root_world_xy"], [80,184])
        self.assertFalse(placed[1]["moved"])
        self.assertTrue(placed[0]["moved"])

    def test_unsupported_large_repair_fails_instead_of_silently_repositioning(self):
        cells = {(x,y) for x in range(10) for y in range(10)}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "all-wall.png"
            Image.new("L", (320,320), 255).save(path)
            with self.assertRaises(ValueError):
                geometry.place_ores({"markers": [marker("iron-01",160,160)]}, ROOT, cells, path)

    def test_cached_art_does_not_hide_a_later_mismatched_canonical_scene(self):
        cells = {(x,y) for x in range(10) for y in range(10)}
        wrong = marker("iron-02",256,160)
        wrong["canonical_native_scene"] = "res://scenes/MapProps/OreNodes/BlackstoneFull.tscn"
        with self.assertRaises(ValueError):
            geometry.place_ores({"markers": [marker("iron-01",160,160), wrong]}, ROOT, cells)


if __name__ == "__main__":
    unittest.main()
