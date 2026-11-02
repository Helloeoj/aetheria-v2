"""Regression checks for the actor's native pose registration contract."""
import json
from pathlib import Path
import unittest

from PIL import Image

from tools.build_player_pose_anchors import register_head

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "godot_client/Assets/Equipment/fitted_bronze_iron"
SE_WALK = [[0, 2], [1, 1], [3, 0], [5, 1], [4, 2], [5, 1], [4, 0], [2, 1]]


class PlayerPoseAnchorsTest(unittest.TestCase):
    def test_registration_recovers_native_motion_despite_palette_conversion(self):
        original = Image.new("RGBA", (80, 80))
        generated = Image.new("RGBA", (80, 80))
        # An asymmetric crown and face; translation is known independently.
        for y in range(15, 34):
            for x in range(30 + (y % 3), 46 - (y % 2)):
                color = (80 + x, 50 + y, 30 + x % 4, 255)
                original.putpixel((x, y), color)
                generated.putpixel((x + 3, y + 2),
                                   (color[0] - 5, color[1] - 4, color[2] - 1, 255))
        self.assertEqual(register_head(original, generated)["offset"], [3, 2])

    def test_southeast_head_follows_the_generated_torso_motion(self):
        poses = json.loads((PACK / "replacement-v1/poses.json").read_text())
        self.assertEqual(
            [poses["south-east"]["run"][str(i)].get("bodyOffset") for i in range(8)],
            SE_WALK,
        )

    def test_every_idle_and_walk_pose_has_a_bounded_native_registration(self):
        poses = json.loads((PACK / "replacement-v1/poses.json").read_text())
        count = 0
        for direction in poses.values():
            for action in direction.values():
                for pose in action.values():
                    count += 1
                    for field in ("bodyOffset", "headOffset"):
                        offset = pose.get(field)
                        self.assertIsInstance(offset, list, field)
                        self.assertEqual(len(offset), 2)
                        self.assertTrue(all(isinstance(v, int) for v in offset))
                        self.assertLessEqual(abs(offset[0]), 8)
                        self.assertLessEqual(abs(offset[1]), 6)
                    self.assertEqual(pose["headOffset"][0], pose["bodyOffset"][0])
                    self.assertIn(pose["headOffset"][1] - pose["bodyOffset"][1], (0, 1, 2))
        self.assertEqual(count, 72)


if __name__ == "__main__":
    unittest.main()
