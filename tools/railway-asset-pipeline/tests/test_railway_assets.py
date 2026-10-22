#!/usr/bin/env python3
"""Synthetic tests. No purchased/proprietary assets are bundled in the repository."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "railway_assets.py"
SPEC = importlib.util.spec_from_file_location("railway_assets", SOURCE)
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


def name_token(value):
    blob = value.encode("cp932")
    return struct.pack("<HI", 1, len(blob)) + blob


def mark(c):
    return struct.pack("<H", assets.MARKS.index(c) + 10)


def uint(value):
    return struct.pack("<HI", 3, value)


def floats(values):
    return struct.pack("<HI", 7, len(values)) + struct.pack("<" + "f" * len(values), *values)


def ints(values):
    return struct.pack("<HI", 6, len(values)) + struct.pack("<" + "I" * len(values), *values)


def toy_x(frame="_t_railway_01"):
    return (assets.X_HEADER + name_token("Frame") + name_token(frame) + mark("{")
            + name_token("Mesh") + name_token("test") + mark("{")
            + uint(3) + floats([0, 0, 0, 1, 0, 0, 0, 1, 0])
            + uint(1) + uint(3) + ints([0, 1, 2])
            + name_token("MeshTextureCoords") + mark("{")
            + uint(3) + floats([0, 0, 1, 0, 0, 1])
            + mark("}") + mark("}") + mark("}"))


def toy_dds(width=4, height=4):
    data = bytearray(128 + 8)
    data[:4] = b"DDS "
    struct.pack_into("<I", data, 4, 124)
    struct.pack_into("<II", data, 12, height, width)
    data[84:88] = b"DXT1"
    return bytes(data)


def resource(name, payload, texture=False):
    header = name.encode("utf-16le").ljust(512, b"\x00")
    if texture:
        height, width = struct.unpack_from("<II", payload, 12)
        return header + struct.pack("<III", width, height, len(payload)) + payload
    return header + struct.pack("<I", len(payload)) + payload


class CatalogTests(unittest.TestCase):
    def test_named_resource_and_exact_end(self):
        data = struct.pack("<I", 2) + resource("train_form.csv", b"hello") + resource("train_pattern.csv", b"world")
        rows = assets.named_records(data, textures=False)
        self.assertEqual([r["name"] for r in rows], ["train_form.csv", "train_pattern.csv"])
        self.assertEqual(data[rows[0]["offset"]:rows[0]["offset"] + rows[0]["size"]], b"hello")
        with self.assertRaises(assets.FormatError):
            assets.named_records(data + b"\x00", textures=False)

    def test_texture_catalog_and_validation(self):
        tex = toy_dds()
        data = struct.pack("<I", 1) + resource("rail_body.dds", tex, texture=True)
        rows = assets.named_records(data, textures=True)
        self.assertEqual((rows[0]["width"], rows[0]["height"]), (4, 4))
        bad = bytearray(data)
        struct.pack_into("<I", bad, 4 + 512, 8)
        with self.assertRaises(assets.FormatError):
            assets.named_records(bytes(bad), textures=True)

    def test_rejects_unsafe_names_and_duplicates(self):
        self.assertEqual(assets.safe_name(r"a\rail\body.dds"), "body.dds")
        with self.assertRaises(assets.FormatError):
            assets.safe_name("../..")
        duplicate = struct.pack("<I", 2) + resource("a.csv", b"a") + resource("A.csv", b"b")
        with self.assertRaises(assets.FormatError):
            assets.named_records(duplicate, textures=False)


class ModelTests(unittest.TestCase):
    def test_binary_x_and_adx_section(self):
        x = toy_x()
        data = b"preamble" + b"ADX0" + struct.pack("<II", 267, len(x)) + x
        result = assets.x_records(data, "vp")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["name_guess"], "_t_railway_01")
        self.assertEqual(result[0]["body_start"], len(b"preamble") + 12)
        self.assertEqual(bytes(data[result[0]["body_start"]:]), x)

    def test_invalid_or_truncated_adx_ignored(self):
        x = toy_x()
        data = b"ADX0" + struct.pack("<II", 267, len(x) + 80) + x
        self.assertEqual(assets.x_records(data, "vp"), [])

    def test_longest_family_wins(self):
        self.assertEqual(assets.model_family("_t_227_1000_a", {"227", "227_1000"}), "227_1000")
        self.assertEqual(assets.model_family("_d_227_b", {"227", "227_1000"}), "227")
        self.assertEqual(assets.model_family("_t_99_a", {"227", "227_1000"}), None)

    def test_select_formation_without_mixing_variants(self):
        def form(name):
            row = [""] * 29
            row[0] = "FORM_" + name.upper()
            row[19] = "Railway " + name
            return row
        def pattern(form_id, prefix, token):
            row = [""] * 18
            row[0] = form_id
            row[1] = prefix
            row[2] = token
            row[6] = "1"
            row[17] = "1"
            return row
        records = [
            {"index": 0, "name_guess": "_t_227_a", "source_x": "vp_0000.x", "body_start": 12, "bytes": 100},
            {"index": 1, "name_guess": "_t_227_1000_a", "source_x": "vp_0001.x", "body_start": 112, "bytes": 100}
        ]
        forms = [form("227"), form("227_1000")]
        patterns = [pattern("FORM_227", "227", "_t_227_a"),
                    pattern("FORM_227_1000", "227_1000", "_t_227_1000_a")]
        vehicles = assets.select_vehicle_records(forms, patterns, records, start=0, count=2)
        self.assertEqual([v["model_chunk_count"] for v in vehicles], [1, 1])
        self.assertEqual([v["formations"][0]["length"] for v in vehicles], [1, 1])

    def test_glb_round_trip_optional(self):
        try:
            import trimesh
            import numpy
            from PIL import Image
        except ImportError:
            self.skipTest("Optional conversion dependencies not installed")
        with tempfile.TemporaryDirectory() as tmp:
            original = Path(tmp) / "source.x"
            dest = Path(tmp) / "converted.glb"
            original.write_bytes(toy_x())
            stats = assets.convert_x_to_glb(original, dest)
            self.assertEqual(stats["triangles"], 1)
            self.assertTrue(dest.is_file())
            self.assertTrue(trimesh.load(dest, force="scene").geometry)


class StreamDecoderTests(unittest.TestCase):
    def test_compiled_decoder_round_trip(self):
        compiler = shutil.which("c++")
        if not compiler:
            self.skipTest("C++17 compiler unavailable")
        path = SOURCE.parent / "decode_unpack.cpp"
        text = path.read_text(encoding="utf-8")
        fixed = [int(s, 16) for s in re.findall(r"0x([0-9a-f]{2})", text.split("};", 1)[0])]
        self.assertEqual(len(fixed), 256)
        clear = b"Railway synthetic unit test: one two three!"
        encoded = bytearray()
        for i in range(0, len(clear), 8):
            part = clear[i:i + 8]
            encoded.append((1 << len(part)) - 1)
            encoded.extend(part)
        key = bytes(range(16))
        cipher = bytes(((value ^ key[i % 16]) - fixed[i % 256]) & 255
                       for i, value in enumerate(encoded))
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "railway-decode"
            subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra",
                            str(path), "-o", str(binary)], check=True, capture_output=True)
            source = Path(tmp) / "fixture.bin"
            result = Path(tmp) / "decoded.bin"
            source.write_bytes(key + cipher)
            subprocess.run([str(binary), str(source), str(result)], check=True, capture_output=True)
            self.assertEqual(result.read_bytes(), clear)


if __name__ == "__main__":
    unittest.main()
