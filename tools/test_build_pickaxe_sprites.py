"""Keep reproducible pickaxe exports compatible with the installed character rig."""
from pathlib import Path
import tempfile
import unittest

from PIL import Image

import build_pickaxe_sprites as builder


class PickaxeExportTests(unittest.TestCase):
    def test_export_preserves_installed_directional_art_and_motion_bindings(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "export"
            manifest = builder.build(output)
            self.assertEqual(len(manifest["entries"]), 7)
            for entry in manifest["entries"]:
                material = entry["id"]
                installed = builder.ROOT / "godot_client" / entry["scene"].removeprefix("res://")
                self.assertEqual((output / "scenes" / (material + ".tscn")).read_text(),
                                 installed.read_text(), material + " must retain current grip/motion contract")
                for direction, view in entry["views"].items():
                    runtime = builder.ROOT / "godot_client" / view["texture"].removeprefix("res://")
                    with Image.open(output / "textures" / material / (direction + ".png")) as exported:
                        with Image.open(runtime) as current:
                            self.assertEqual(exported.convert("RGBA").tobytes(),
                                             current.convert("RGBA").tobytes(), material + "/" + direction)


if __name__ == "__main__":
    unittest.main()
