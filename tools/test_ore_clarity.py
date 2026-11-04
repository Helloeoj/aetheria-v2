"""Exercise art-only installation in isolated replicas; never touches live Godot."""
from pathlib import Path
import importlib.util
import json
import re
import shutil
import tempfile
import unittest

from PIL import Image, ImageDraw, ImageChops

ROOT = Path(__file__).resolve().parents[1]
MODULE = Path(__file__).with_name("install_ore_clarity.py")
spec = importlib.util.spec_from_file_location("install_ore_clarity", MODULE)
clarity = importlib.util.module_from_spec(spec) if MODULE.exists() else None
if clarity:
    spec.loader.exec_module(clarity)


class OreClarityTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(clarity, "Art-only installer is not implemented")
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        for relative in ("tools/ore-integration", "godot_client/scenes/MapProps/OreNodes",
                         "godot_client/Assets/MapTiles/OreNodes", "godot_client/Assets/Tilesets"):
            shutil.copytree(ROOT / relative, self.repo / relative, ignore=shutil.ignore_patterns("Detail128"))
        self.source = self.repo / "art_sources/ore-nodes/detail-v1"
        self.source.mkdir(parents=True)
        self.baseline = json.loads((self.repo / "tools/ore-integration/original-library.json").read_text())
        with Image.open(self.repo / "godot_client/Assets/MapTiles/OreNodes/copper-ore-depleted-south.png") as old:
            alpha = old.getchannel("A").resize((128,128), Image.Resampling.BILINEAR).point(lambda v: 255 if v >= 128 else 0)
        base = Image.new("RGBA", (128, 128), (65,72,80,0))
        base.putalpha(alpha)
        mask = Image.new("L", (128, 128))
        ImageDraw.Draw(mask).rectangle((44, 54, 61, 66), fill=255)
        mask = ImageChops.multiply(mask, alpha)
        mask.save(self.source / "vein-mask.png")
        for index, entry in enumerate(self.baseline["entries"]):
            for state in ("full", "depleted"):
                image = base.copy()
                if state == "full":
                    image.paste((95 + index * 10, 140, 165, 255), (0,0,128,128), mask)
                image.save(self.source / Path(entry[state]["texture"]).name)

    def plan(self):
        return clarity.install(self.repo, self.source, apply=False)

    def test_dry_run_never_writes_and_apply_retains_scene_geometry_and_palettes(self):
        before = {p.relative_to(self.repo): p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        report = self.plan()
        self.assertEqual(report["textures"], 20)
        self.assertFalse((self.repo / "godot_client/Assets/MapTiles/OreNodes/Detail128").exists())
        self.assertEqual(before, {p.relative_to(self.repo): p.read_bytes() for p in self.repo.rglob("*") if p.is_file()})
        clarity.install(self.repo, self.source, apply=True)
        manifest = json.loads((self.repo / "godot_client/Assets/MapTiles/OreNodes/manifest.json").read_text())
        self.assertEqual(manifest["native_canvas_size"], [128, 128])
        self.assertEqual(manifest["world_canvas_size"], [96, 96])
        self.assertEqual(manifest["native_scale"], 1)
        for entry, original in zip(manifest["entries"], self.baseline["entries"]):
            self.assertEqual(entry["collision_polygons"], original["collision_polygons"])
            self.assertEqual(entry["anchor"], [64, 96])
            self.assertEqual(entry["world_anchor"], [48, 72])
            for state in ("full", "depleted"):
                self.assertEqual(entry[state]["scene"], original[state]["scene"])
                self.assertEqual(entry[state]["tile_id"], original[state]["tile_id"])
                texture = self.repo / "godot_client" / entry[state]["texture"].removeprefix("res://")
                self.assertEqual(texture.read_bytes(), (self.source / texture.name).read_bytes())
                text = (self.repo / "godot_client" / entry[state]["scene"].removeprefix("res://")).read_text()
                self.assertIn("position = Vector2(-48, -72)", text)
                self.assertIn("scale = Vector2(0.75, 0.75)", text)
                visual = next(section for section in re.split(r"(?=^\[node )", text, flags=re.MULTILINE)
                              if section.startswith('[node name="Visual"'))
                position = tuple(float(v) for v in re.search(r"position = Vector2\(([^)]+)\)", visual)[1].split(","))
                scale = tuple(float(v) for v in re.search(r"scale = Vector2\(([^)]+)\)", visual)[1].split(","))
                self.assertEqual((*position, 128 * scale[0], 128 * scale[1]), (-48,-72,96,96))
                self.assertEqual((position[0] + 64 * scale[0], position[1] + 96 * scale[1]), (0,0))
                original_scene = json.loads((self.repo / "tools/ore-integration/original-scenes.json").read_text())[original[state]["scene"]]
                self.assertEqual(re.findall(r"^polygon = .+$", text, flags=re.MULTILINE),
                                 re.findall(r"^polygon = .+$", original_scene, flags=re.MULTILINE))
                root = next(section for section in re.split(r"(?=^\[node )", text, flags=re.MULTILINE)
                            if section.startswith('[node ') and 'type="Node2D"' in section.partition("\n")[0])
                self.assertNotRegex(root, r"(?m)^scale =")
        for relative, contents in before.items():
            if relative.suffix == ".tres" or relative.suffix == ".png":
                self.assertEqual((self.repo / relative).read_bytes(), contents)
        # Re-running verifies runtime sources/imports and is safe and idempotent.
        installed = {p: p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        clarity.install(self.repo, self.source, apply=True)
        self.assertEqual(installed, {p: p.read_bytes() for p in self.repo.rglob("*") if p.is_file()})

    def test_rejects_partial_alpha_stray_pixel_and_clipped_silhouette_before_writes(self):
        path = self.source / "copper-ore-full-south.png"
        original = path.read_bytes()
        for point, rgba in (((50, 50), (60, 60, 60, 128)), ((1, 1), (60, 60, 60, 255)),
                            ((0, 50), (60, 60, 60, 255))):
            path.write_bytes(original)
            image = Image.open(path).convert("RGBA")
            image.putpixel(point, rgba)
            image.save(path)
            with self.assertRaises(ValueError):
                clarity.install(self.repo, self.source, apply=True)
            self.assertFalse((self.repo / "godot_client/Assets/MapTiles/OreNodes/Detail128").exists())

    def test_rejects_host_repaint_outside_vein_mask(self):
        path = self.source / "copper-ore-full-south.png"
        image = Image.open(path).convert("RGBA")
        image.putpixel((90, 90), (110, 120, 130, 255))
        image.save(path)
        with self.assertRaisesRegex(ValueError, "host"):
            self.plan()

    def test_rejects_different_depleted_bytes_and_native_size(self):
        path = self.source / "copper-ore-depleted-south.png"
        original = path.read_bytes()
        image = Image.open(path).convert("RGBA")
        image.putpixel((90, 90), (110, 120, 130, 255))
        image.save(path)
        with self.assertRaises(ValueError):
            self.plan()
        path.write_bytes(original)
        Image.new("RGBA", (96, 96)).save(path)
        with self.assertRaisesRegex(ValueError, "128"):
            self.plan()

    def test_refuses_existing_scene_collider_or_gameplay_edits(self):
        path = self.repo / "godot_client/scenes/MapProps/OreNodes/CopperOreFull.tscn"
        original = path.read_text()
        for text in (original.replace("8, -15", "9, -15"),
                     original.replace("y_sort_enabled = true", "y_sort_enabled = false"),
                     original.replace("position = Vector2(-48, -72)", "position = Vector2(-47, -72)")):
            path.write_text(text)
            with self.assertRaisesRegex(ValueError, "scene"):
                self.plan()

    def test_rejects_original_asset_mutation(self):
        path = self.repo / "godot_client/Assets/MapTiles/OreNodes/copper-ore-full-south.png"
        path.write_bytes(b"overwritten")
        with self.assertRaisesRegex(ValueError, "original"):
            self.plan()

    def test_rejects_shared_silhouette_change_even_when_all_twenty_alphas_match(self):
        for path in self.source.glob("*-south.png"):
            image = Image.open(path).convert("RGBA")
            image.putpixel((50,50), (*image.getpixel((50,50))[:3], 0))
            image.save(path)
        with self.assertRaisesRegex(ValueError, "silhouette.*original|original.*silhouette"):
            self.plan()

    def test_refuses_to_discard_unrecognized_manifest_work(self):
        path = self.repo / "godot_client/Assets/MapTiles/OreNodes/manifest.json"
        manifest = json.loads(path.read_text())
        manifest["entries"][0]["artist_note"] = "Unrelated pending work"
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "Manifest.*unrecognized"):
            self.plan()


class CanonicalSourceTests(unittest.TestCase):
    def test_authored_source_batch_passes_without_modifying_runtime(self):
        self.assertIsNotNone(clarity)
        before = {p: p.read_bytes() for p in (ROOT / "godot_client/scenes/MapProps/OreNodes").glob("*.tscn")}
        manifest = ROOT / "godot_client/Assets/MapTiles/OreNodes/manifest.json"
        before[manifest] = manifest.read_bytes()
        report = clarity.install(ROOT, apply=False)
        self.assertEqual(report["textures"], 20)
        self.assertEqual(report["vein_mask"], "explicit")
        full = [value for name, value in report["source_sha256"].items() if "-full-" in name]
        depleted = [value for name, value in report["source_sha256"].items() if "-depleted-" in name]
        self.assertEqual(len(set(full)), 10)
        self.assertEqual(len(depleted), 10)
        self.assertEqual(len(set(depleted)), 1)
        self.assertEqual(before, {p: p.read_bytes() for p in before})


if __name__ == "__main__":
    unittest.main()
