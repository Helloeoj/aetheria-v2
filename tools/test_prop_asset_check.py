"""Regression fixtures for native prop PNG checks; never edit installed art."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from PIL import Image

try:
    from prop_asset_check import check_asset
except ModuleNotFoundError:
    check_asset = None


class PropAssetCheckTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(check_asset, "Native prop asset checker is not implemented")
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.project = Path(self.directory.name)
        self.texture = self.project / "props" / "rock.png"
        self.texture.parent.mkdir()
        self.image = Image.new("RGBA", (12, 12))
        # A hand-authored 4x4 silhouette, well clear of the canvas borders.
        for y in range(4, 8):
            for x in range(4, 8):
                self.image.putpixel((x, y), (100, 90, 70, 255))
        self.spec = {
            "texture": "res://props/rock.png",
            "native_size": [12, 12],
            "anchor": [6, 8],
        }
        self.save()
        self.write_import()

    def save(self):
        self.image.save(self.texture)

    def write_import(self, params=None):
        if params is None:
            params = "compress/mode=0\nmipmaps/generate=false\nprocess/size_limit=0\n"
        self.texture.with_suffix(".png.import").write_text(
            '[remap]\nimporter="texture"\nmetadata={\n"vram_texture": false\n}\n'
            "[params]\n" + params,
            encoding="utf-8",
        )

    def check(self):
        return check_asset(self.project, self.spec)

    def assert_issue(self, code):
        result = self.check()
        self.assertFalse(result["passed"], result)
        self.assertIn(code, [issue["code"] for issue in result["issues"]], result)
        return result

    def test_clean_native_png_passes_without_certifying_visual_review(self):
        result = self.check()
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["issues"], [])
        self.assertTrue(result["visual_review_required"])

    def test_wrong_native_canvas_is_rejected(self):
        self.spec["native_size"] = [24, 24]
        self.assert_issue("native_size")

    def test_empty_png_is_rejected(self):
        self.image = Image.new("RGBA", (12, 12))
        self.save()
        self.assert_issue("empty_art")

    def test_silhouette_at_canvas_edge_is_rejected(self):
        for x in range(5):
            self.image.putpixel((x, 4), (100, 90, 70, 255))
        self.save()
        self.assert_issue("clipped_edge")

    def test_isolated_stray_pixel_is_rejected(self):
        self.image.putpixel((1, 1), (100, 90, 70, 255))
        self.save()
        self.assert_issue("tiny_components")

    def test_diagonal_pixels_form_one_eight_connected_component(self):
        self.image = Image.new("RGBA", (12, 12))
        for coordinate in ((4, 4), (5, 5), (6, 6)):
            self.image.putpixel(coordinate, (100, 90, 70, 255))
        self.save()
        self.assertTrue(self.check()["passed"])

    def test_component_threshold_is_honored(self):
        self.image.putpixel((1, 1), (100, 90, 70, 255))
        self.image.putpixel((2, 1), (100, 90, 70, 255))
        self.save()
        self.assert_issue("tiny_components")
        self.spec["min_component_pixels"] = 2
        self.assertTrue(self.check()["passed"])

    def test_partial_alpha_is_rejected(self):
        self.image.putpixel((4, 4), (100, 90, 70, 128))
        self.save()
        self.assert_issue("partial_alpha")

    def test_partial_palette_alpha_is_rejected(self):
        image = Image.new("P", (12, 12))
        image.putpalette([0, 0, 0, 100, 90, 70] + [0] * 762)
        for y in range(4, 8):
            for x in range(4, 8):
                image.putpixel((x, y), 1)
        image.save(self.texture, transparency=bytes([0, 128]))
        self.assert_issue("partial_alpha")

    def test_explicit_exceptions_are_visible_and_do_not_hide_other_failures(self):
        self.image.putpixel((1, 1), (100, 90, 70, 128))
        self.save()
        self.spec["alpha_reason"] = "Reviewed intentional translucent glint."
        result = self.assert_issue("tiny_components")
        self.assertNotIn("partial_alpha", [item["code"] for item in result["issues"]])
        self.assertEqual(result["exceptions"][0]["reason"], self.spec["alpha_reason"])
        self.spec["components_reason"] = "Reviewed intentional detached glint."
        result = self.check()
        self.assertTrue(result["passed"], result)
        self.assertEqual(len(result["exceptions"]), 2)

    def test_edge_exception_requires_nonempty_review_reason(self):
        self.spec["edge_reason"] = " "
        self.assert_issue("invalid_spec")

    def test_reviewed_edge_overhang_is_visible_in_report(self):
        for x in range(5):
            self.image.putpixel((x, 4), (100, 90, 70, 255))
        self.save()
        self.spec["edge_reason"] = "Reviewed intentional tiling seam."
        result = self.check()
        self.assertTrue(result["passed"], result)
        self.assertTrue(result["exceptions"][0]["applied"])

    def test_import_must_be_lossless_and_without_mipmaps(self):
        self.write_import("compress/mode=1\nmipmaps/generate=true\n")
        result = self.assert_issue("import_lossy")
        self.assertIn("import_mipmaps", [item["code"] for item in result["issues"]])

    def test_missing_or_ambiguous_import_settings_are_rejected(self):
        for params in ("", "compress/mode=0\n", "compress/mode=0\ncompress/mode=1\nmipmaps/generate=false\n"):
            with self.subTest(params=params):
                self.write_import(params)
                self.assert_issue("import_settings")

    def test_import_size_limit_cannot_resize_native_art(self):
        self.write_import("compress/mode=0\nmipmaps/generate=false\nprocess/size_limit=8\n")
        self.assert_issue("import_resize")

    def test_missing_import_file_is_rejected(self):
        self.texture.with_suffix(".png.import").unlink()
        self.assert_issue("import_missing")

    def test_non_png_contents_and_extension_are_rejected(self):
        self.texture.write_bytes(b"not a PNG")
        self.assert_issue("invalid_png")
        self.image.convert("RGB").save(self.texture, format="GIF")
        self.assert_issue("invalid_png")
        self.spec["texture"] = "res://props/rock.jpg"
        self.assert_issue("invalid_texture")

    def test_missing_source_is_rejected(self):
        self.texture.unlink()
        self.assert_issue("missing_texture")

    def test_malformed_spec_values_return_structured_failures(self):
        variants = [None, [], {}, {**self.spec, "native_size": [0, 12]},
                    {**self.spec, "native_size": [True, 12]},
                    {**self.spec, "native_size": [12.0, 12]},
                    {**self.spec, "anchor": [float("nan"), 8]},
                    {**self.spec, "anchor": [10 ** 1000, 8]},
                    {**self.spec, "anchor": [6]},
                    {**self.spec, "anchor": ["6", 8]},
                    {**self.spec, "anchor": [13, 8]},
                    {**self.spec, "min_component_pixels": 0},
                    {**self.spec, "alpha_reason": False}]
        for spec in variants:
            with self.subTest(spec=spec):
                result = check_asset(self.project, spec)
                self.assertFalse(result["passed"], result)
                self.assertIn("invalid_spec", [item["code"] for item in result["issues"]])

    def test_paths_must_use_res_and_stay_inside_project(self):
        for texture in ("../rock.png", "res://../../escape.png", "C:/outside.png", "res://props\\rock.png"):
            with self.subTest(texture=texture):
                self.spec["texture"] = texture
                self.assert_issue("invalid_texture")

    def test_source_and_import_symlinks_cannot_escape_project(self):
        with tempfile.TemporaryDirectory() as outside_directory:
            outside = Path(outside_directory)
            external = outside / "external.png"
            self.image.save(external)
            self.texture.unlink()
            try:
                self.texture.symlink_to(external)
            except OSError as error:
                self.skipTest(f"Symlinks are unavailable on this machine: {error}")
            self.assert_issue("invalid_texture")
            self.texture.unlink()
            self.save()
            import_path = self.texture.with_suffix(".png.import")
            external_import = outside / "external.png.import"
            external_import.write_bytes(import_path.read_bytes())
            import_path.unlink()
            import_path.symlink_to(external_import)
            self.assert_issue("import_settings")

    def test_checks_do_not_change_source_or_import_bytes(self):
        paths = (self.texture, self.texture.with_suffix(".png.import"))
        before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
        self.assertTrue(self.check()["passed"])
        after = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
