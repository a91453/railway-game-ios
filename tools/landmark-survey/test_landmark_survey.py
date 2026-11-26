#!/usr/bin/env python3
"""Tests of survey.py and landmark_check.py without the network or an extract:

    uv run --with numpy python -I tools/landmark-survey/test_landmark_survey.py
"""

import json
import math
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import landmark_check  # noqa: E402
import survey  # noqa: E402


def glb(path, triangles, colours=None):
    """A GLB of `triangles` (n, 3, 3) in glTF axes, one material per colour index."""
    triangles = np.asarray(triangles, np.float32)
    colours = colours or [0] * len(triangles)
    blob, meshes, accessors, views, prims = b"", [], [], [], []
    for c in sorted(set(colours)):
        pts = triangles[[i for i, k in enumerate(colours) if k == c]].reshape(-1, 3)
        idx = np.arange(len(pts), dtype=np.uint32)
        for data, kind, typ in ((pts.tobytes(), 5126, "VEC3"), (idx.tobytes(), 5125, "SCALAR")):
            views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
            acc = {"bufferView": len(views) - 1, "componentType": kind, "count": len(pts), "type": typ}
            if typ == "VEC3":
                acc["min"], acc["max"] = pts.min(0).tolist(), pts.max(0).tolist()
            accessors.append(acc)
            blob += data
        prims.append({"attributes": {"POSITION": len(accessors) - 2}, "indices": len(accessors) - 1, "material": c})
    meshes.append({"primitives": prims})
    gltf = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
            "meshes": meshes, "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
            "materials": [{"name": f"m{c}", "pbrMetallicRoughness": {"baseColorFactor": [c / 10, 0.5, 0.5, 1]}}
                          for c in range(max(colours) + 1)]}
    text = json.dumps(gltf).encode()
    text += b" " * (-len(text) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\0") + blob
    Path(path).write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def cuboid(L, W, H, lid=True):
    """A box L (x) × W × H standing on y = 0 in glTF axes (y up), faces out."""
    x, z = L / 2, W / 2
    v = {k: np.array(p, float) for k, p in {
        "a": (-x, 0, -z), "b": (x, 0, -z), "c": (x, 0, z), "d": (-x, 0, z),
        "e": (-x, H, -z), "f": (x, H, -z), "g": (x, H, z), "h": (-x, H, z)}.items()}
    quads = ["adcb", "abfe", "bcgf", "cdhg", "daeh"] + (["efgh"] if lid else [])
    tris = []
    for q in quads:
        p = [v[k] for k in q]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        mid = sum(p) / 4 - np.array([0, H / 2, 0])
        if n @ mid < 0:
            p = p[::-1]
        tris += [[p[0], p[1], p[2]], [p[0], p[2], p[3]]]
    return np.array(tris)


def survey_for(L, W, height=None, estimate=False):
    ring = [[-L / 2, -W / 2], [L / 2, -W / 2], [L / 2, W / 2], [-L / 2, W / 2]]
    return {"footprint": {"ring": ring, "box": survey.box(np.array(ring)), "area": L * W},
            "height": {"value": height, "estimate": estimate, "source": "test"} if height else None}


class Check(unittest.TestCase):
    def run_check(self, tris, s=None, colours=None, extra=()):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "m.glb"
            glb(path, tris, colours)
            args = [str(path)]
            if s:
                Path(d, "s.json").write_text(json.dumps(s))
                args += ["--survey", str(Path(d) / "s.json")]
            return landmark_check.main(args + list(extra))

    def test_a_closed_box_of_the_surveyed_size_passes(self):
        self.assertEqual(self.run_check(cuboid(20, 12, 18), survey_for(20, 12, 18)), 0)

    def test_an_open_top_fails(self):
        # the back of the far walls shows from above: Pocket City's open shaft
        self.assertEqual(self.run_check(cuboid(20, 12, 18, lid=False), survey_for(20, 12, 18)), 1)

    def test_a_box_too_long_fails(self):
        self.assertEqual(self.run_check(cuboid(23, 12, 18), survey_for(20, 12, 18)), 1)

    def test_too_tall_fails_but_an_estimate_only_prints(self):
        self.assertEqual(self.run_check(cuboid(20, 12, 24), survey_for(20, 12, 18)), 1)
        self.assertEqual(self.run_check(cuboid(20, 12, 24), survey_for(20, 12, 18, estimate=True)), 0)

    def test_a_ground_plate_fails(self):
        plate = np.array([[[-30, 0, -30], [-30, 0, 30], [30, 0, 30]], [[-30, 0, -30], [30, 0, 30], [30, 0, -30]]], float)
        tris = np.concatenate([cuboid(20, 12, 18), plate])
        self.assertEqual(self.run_check(tris), 1)
        self.assertEqual(self.run_check(tris, extra=["--allow-ground-plate"]), 0)

    def test_two_colours_in_one_plane_fail(self):
        box = cuboid(20, 12, 18)
        lid = box[-2:].copy()
        tris = np.concatenate([box, lid[:, ::-1][:, [0, 2, 1]]])
        self.assertEqual(self.run_check(tris, colours=[0] * len(box) + [1, 1]), 1)


class Survey(unittest.TestCase):
    def test_box_of_a_turned_rectangle(self):
        t = math.radians(30)
        rot = np.array([[math.cos(t), -math.sin(t)], [math.sin(t), math.cos(t)]])
        ring = np.array([[-10, -4], [10, -4], [10, 4], [-10, 4]]) @ rot.T
        b = survey.box(ring)
        self.assertAlmostEqual(b["L"], 20, 2)
        self.assertAlmostEqual(b["W"], 8, 2)
        self.assertAlmostEqual(b["bearing"], 60, 1)

    def test_png_and_both_elevation_codes(self):
        rgb = np.array([[[0, 39, 16], [128, 0, 0]], [[255, 255, 156], [128, 0, 0]]], np.uint8)   # 100.00 m, no data, -1.00 m
        raw = b"".join(b"\x00" + bytes(r.reshape(-1)) for r in rgb)

        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0)) + \
            chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
        h = survey.decode("dem5a_png", survey.png_rgb(png))
        self.assertAlmostEqual(h[0, 0], 100.0)
        self.assertTrue(math.isnan(h[0, 1]))
        self.assertAlmostEqual(h[1, 0], -1.0)
        self.assertAlmostEqual(survey.decode("terrarium", np.array([[[128, 10, 128]]]))[0, 0], 10.5)

    def test_picks_the_named_building_and_what_it_covers(self):
        lat, lon = 33.8845, 130.8741

        def square(cx, cy, half):
            dlat, dlon = 1 / 110574.0, 1 / (111320.0 * math.cos(math.radians(lat)))
            return [[lat + (cy + y) * dlat, lon + (cx + x) * dlon] for x, y in ((-half, -half), (half, -half), (half, half), (-half, half))]
        osm = {"lat": lat, "lon": lon, "read": "2026-11-26", "source": "test", "elements": [
            {"ref": "way/1", "type": "area", "tags": {"building": "yes", "name": "小倉城", "height": "18.8", "wikidata": "Q1"},
             "rings": [square(0, 0, 10)]},
            {"ref": "way/2", "type": "area", "tags": {"building": "yes"}, "rings": [square(2, 2, 2)]},
            {"ref": "way/3", "type": "area", "tags": {"building": "yes", "name": "庭園", "tourism": "museum"},
             "rings": [square(40, 0, 5)]},
            {"ref": "way/4", "type": "area", "tags": {"building:part": "yes", "height": "6"}, "rings": [square(0, 0, 9)]}]}
        with tempfile.TemporaryDirectory() as d:
            r = survey.survey(osm, lat, lon, None, "小倉", 200, "none", None, d)
            self.assertTrue(Path(d, "plan.svg").exists() and Path(d, "survey.md").exists())
        self.assertEqual(r["ref"], "way/1")
        self.assertAlmostEqual(r["footprint"]["box"]["L"], 20, 1)
        self.assertEqual(r["height"]["value"], 18.8)
        self.assertFalse(r["height"]["estimate"])
        self.assertEqual([c["ref"] for c in r["covers"]], ["way/2"])
        self.assertEqual([p["ref"] for p in r["parts"]], ["way/4"])
        self.assertEqual([f["ref"] for f in r["famous"]], ["way/3"])


if __name__ == "__main__":
    unittest.main()
