"""Fail-closed orchestration regressions; real physics is tested by Godot."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

try:
    import worldbuilding
    from worldbuilding import load_contract, require_external_report, run_godot
except ImportError:
    load_contract = require_external_report = run_godot = None


class WorldbuildingRunnerTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(load_contract, "worldbuilding runner must exist")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "repo" / "godot_client"
        self.project.mkdir(parents=True)
        (self.project / "test.tscn").write_text("[gd_scene format=3]\n")
        self.manifest = self.base / "contract.json"
        self.report = self.base / "report.json"

    def contract(self, **changes):
        data = {"schema_version": 1, "scene": "res://test.tscn", "assets": [
            {"texture": "res://test.png", "native_size": [96, 96], "anchor": [48, 72]}]}
        data.update(changes)
        self.manifest.write_text(json.dumps(data), encoding="utf-8")
        return load_contract(self.manifest, self.project)

    def test_contract_rejects_empty_asset_audit(self):
        with self.assertRaisesRegex(ValueError, "assets"):
            self.contract(assets=[])

    def test_contract_rejects_path_escape(self):
        with self.assertRaisesRegex(ValueError, "scene"):
            self.contract(scene="res://../outside.tscn")

    def test_contract_rejects_wrong_schema(self):
        for value in [True, 2, "1"]:
            with self.assertRaisesRegex(ValueError, "schema_version"):
                self.contract(schema_version=value)

    def test_valid_scene_and_asset_contract_loads(self):
        self.assertEqual(self.contract()["scene"], "res://test.tscn")

    def test_reports_cannot_write_generated_evidence_into_repository(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            require_external_report(self.project / "output.json", self.project.parent)
        require_external_report(self.report, self.project.parent)

    def run_fake(self, output="", code=0, geometry=None):
        def complete(*args, **kwargs):
            if geometry is not None:
                self.report.write_text(json.dumps(geometry))
            return subprocess.CompletedProcess(args[0], code, output, "")
        with patch("worldbuilding.subprocess.run", side_effect=complete):
            return run_godot(Path("godot.exe"), self.project, self.manifest, self.report)

    def test_exit_zero_with_script_error_is_rejected(self):
        result = self.run_fake("SCRIPT ERROR: Parse Error", geometry={"passed": True, "checks": 2, "issues": []})
        self.assertFalse(result["passed"])
        self.assertEqual(result["issues"][0]["code"], "engine_error")

    def test_exit_zero_without_report_is_rejected(self):
        self.assertFalse(self.run_fake()["passed"])

    def test_stale_report_is_removed_before_run(self):
        self.report.write_text('{"passed": true, "checks": 2, "issues": []}')
        self.assertFalse(self.run_fake()["passed"])

    def test_nonzero_exit_and_inconsistent_report_are_rejected(self):
        self.assertFalse(self.run_fake(code=1, geometry={"passed": True, "checks": 1, "issues": []})["passed"])
        self.assertFalse(self.run_fake(geometry={"passed": True, "checks": 1, "issues": [{"code": "overlap"}]})["passed"])
        self.assertFalse(self.run_fake(geometry={"passed": True, "checks": 0, "issues": []})["passed"])

    def test_geometry_failure_preserves_actionable_issue(self):
        result = self.run_fake(code=1, geometry={"passed": False, "checks": 2, "issues": [{"code": "prop_overlap", "node": "Props/Rock", "detail": "wall"}]})
        self.assertFalse(result["passed"])
        self.assertEqual(result["issues"][0]["code"], "prop_overlap")

    def test_timeout_fails_without_certifying_scene(self):
        with patch("worldbuilding.subprocess.run", side_effect=subprocess.TimeoutExpired("godot", 55)):
            result = run_godot(Path("godot.exe"), self.project, self.manifest, self.report)
        self.assertFalse(result["passed"])
        self.assertEqual(result["issues"][0]["code"], "engine_timeout")

    def test_geometry_success_remains_unverified_visually(self):
        result = self.run_fake(geometry={"passed": True, "checks": 4, "issues": [], "rendering_verified": False})
        self.assertTrue(result["passed"])
        self.assertFalse(result["rendering_verified"])

    def test_actual_texture_must_have_source_contract(self):
        bind = getattr(worldbuilding, "bind_visuals", None)
        self.assertIsNotNone(bind, "actual scene visuals must be bound to checked source PNGs")
        issues = bind(self.contract()["assets"], [{"texture": "res://other.png", "node": "Rock/Visual", "world_scale": [1, 1], "anchor": [48, 72]}])
        self.assertEqual(issues[0]["code"], "unchecked_prop_texture")

    def test_actual_density_and_anchor_must_match_source_contract(self):
        bind = getattr(worldbuilding, "bind_visuals", None)
        self.assertIsNotNone(bind, "actual density/anchor validation must exist")
        asset = self.contract()["assets"]
        bad = {"texture": "res://test.png", "node": "Rock/Visual", "native_size": [96, 96], "world_scale": [1.5, 1], "anchor": [12, 72]}
        self.assertEqual({issue["code"] for issue in bind(asset, [bad])}, {"prop_density", "prop_anchor"})
        good = dict(bad, world_scale=[0.75, 0.75], anchor=[48, 72])
        asset[0]["world_pixels_per_source_pixel"] = 0.75
        self.assertEqual(bind(asset, [good]), [])

    def test_missing_visual_binding_never_passes(self):
        bind = getattr(worldbuilding, "bind_visuals", None)
        self.assertIsNotNone(bind, "missing geometry/source binding must fail")
        self.assertEqual(bind(self.contract()["assets"], [])[0]["code"], "missing_prop_textures")

    def test_actual_imported_texture_dimensions_must_match_checked_source(self):
        visual = {"texture": "res://test.png", "node": "Rock/Visual", "native_size": [48, 48], "world_scale": [1, 1], "anchor": [48, 72]}
        issues = worldbuilding.bind_visuals(self.contract()["assets"], [visual])
        self.assertEqual([issue["code"] for issue in issues], ["imported_native_size"])
        visual.pop("native_size")
        self.assertEqual(worldbuilding.bind_visuals(self.contract()["assets"], [visual])[0]["code"], "imported_native_size")


if __name__ == "__main__":
    unittest.main()
