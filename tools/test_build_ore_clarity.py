"""Rebuild the accepted ore family in temporary output folders from saved inputs."""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODULE = Path(__file__).with_name("build_ore_clarity.py")
spec = importlib.util.spec_from_file_location("build_ore_clarity", MODULE)
builder = importlib.util.module_from_spec(spec) if MODULE.exists() else None
if builder:
    spec.loader.exec_module(builder)


class OreBuildTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(builder, "Portable source builder is not implemented")

    def test_rebuild_is_deterministic_and_matches_accepted_pixels_and_png_bytes(self):
        accepted = ROOT / "art_sources/ore-nodes/detail-v1"
        before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in accepted.iterdir() if p.is_file()}
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / "one", Path(directory) / "two"
            report = builder.build(ROOT, first)
            builder.build(ROOT, second)
            self.assertEqual(report["alpha_pixels"], 3446)
            self.assertEqual(report["mineral_pixels"], 509)
            self.assertEqual(len(report["files"]), 23)
            for name in report["files"]:
                self.assertEqual((first / name).read_bytes(), (accepted / name).read_bytes(), name)
                self.assertEqual((first / name).read_bytes(), (second / name).read_bytes(), name)
            host = np.array(Image.open(first / "shared-host.png").convert("RGBA"))
            mask = np.array(Image.open(first / "vein-mask.png")) > 0
            self.assertEqual(set(np.unique(host[:, :, 3])), {0,255})
            depleted = []
            for path in first.glob("*-south.png"):
                pixels = np.array(Image.open(path).convert("RGBA"))
                self.assertTrue(np.array_equal(pixels[:, :, 3], host[:, :, 3]))
                self.assertTrue(np.array_equal(pixels[~mask], host[~mask]))
                if "depleted" in path.name:
                    self.assertTrue(np.array_equal(pixels, host))
                    depleted.append(path.read_bytes())
            self.assertEqual(len(depleted), 10)
            self.assertEqual(len(set(depleted)), 1)
        self.assertEqual(before, {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in before})

    def test_refuses_canonical_source_runtime_and_nonempty_output(self):
        for output in (ROOT / "art_sources/ore-nodes/detail-v1", ROOT / "godot_client/Assets/MapTiles/OreNodes/Detail128"):
            with self.assertRaisesRegex(ValueError, "output|Output"):
                builder.build(ROOT, output)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            pending = output / "user-work.txt"
            pending.write_text("retain")
            with self.assertRaisesRegex(ValueError, "empty"):
                builder.build(ROOT, output)
            self.assertEqual(pending.read_text(), "retain")

    def test_portable_inputs_rebuild_without_installed_manifest_or_godot_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "portable-repository"
            ore = repo / "art_sources/ore-nodes"
            detail = ore / "detail-v1"
            detail.mkdir(parents=True)
            support = repo / "tools/ore-integration"
            support.mkdir(parents=True)
            snapshot = ROOT / "tools/ore-integration/original-library.json"
            shutil.copyfile(snapshot, support / snapshot.name)
            manifest = json.loads(snapshot.read_text())
            for entry in manifest["entries"]:
                for state in ("full", "depleted"):
                    name = Path(entry[state]["texture"]).name
                    shutil.copyfile(ROOT / "art_sources/ore-nodes" / name, ore / name)
            shutil.copyfile(ROOT / "art_sources/ore-nodes/tin-shared-shape-provenance.json", ore / "tin-shared-shape-provenance.json")
            for name in ("generated-depleted-host.png", "generated-mithril-template.png"):
                shutil.copyfile(ROOT / "art_sources/ore-nodes/detail-v1" / name, detail / name)
            output = Path(directory) / "rebuilt"
            report = builder.build(repo, output)
            self.assertFalse((repo / "godot_client").exists())
            for name in report["files"]:
                self.assertEqual((output / name).read_bytes(), (ROOT / "art_sources/ore-nodes/detail-v1" / name).read_bytes(), name)
            self.assertTrue(all(not Path(name).is_absolute() for name in report["inputs"]))
            original_host = ore / "copper-ore-depleted-south.png"
            image = Image.open(original_host).convert("RGBA")
            image.putpixel((40,40), (80,90,100,image.getpixel((40,40))[3]))
            image.save(original_host)
            with self.assertRaisesRegex(ValueError, "original96.*snapshot"):
                builder.build(repo,Path(directory)/"modified-original")


if __name__ == "__main__":
    unittest.main()
