"""Fast Blender check for decision 611's revision-3 terrain contact."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RoadTunnelSceneTests(unittest.TestCase):
    def test_ground_contact(self):
        with tempfile.TemporaryDirectory() as output:
            result = subprocess.run(
                ["blender", "-b", "--python", str(ROOT / "tools/road_tunnel_portals.py"),
                 "--", "--output", output, "--composition-only", "--scene-check-only"],
                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("GROUND CONTACT: mountain, wings, roads/rails at 0.000 m", result.stdout)
        self.assertIn("SCENE CHECK PASSED", result.stdout)


if __name__ == "__main__":
    unittest.main()
