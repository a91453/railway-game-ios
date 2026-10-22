#!/usr/bin/env python3
"""Fully synthetic Railway installer-layer tests: no source media or binaries."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

SOURCE = Path(__file__).resolve().parents[1] / "installer_layers.py"
SPEC = importlib.util.spec_from_file_location("installer_layers", SOURCE)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


def encrypt_entry(source, name, *, flags=0):
    key = bytes(b ^ (0x13, 0x35, 0x86, 0x07)[i % 4]
                for i, b in enumerate(name.encode("utf-8")))
    encrypted = bytearray(len(source))
    for i, byte in enumerate(source):
        n = i % 1024 if flags & 4 else i
        swapped = (~byte ^ key[n % len(key)]) & 255
        encrypted[i] = ((swapped << 4) | (swapped >> 4)) & 255
    return bytes(encrypted)


def toy_pe(overlay):
    # Deliberately construct a minimal PE header and section, without executing it.
    data = bytearray(0x300)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3c, 0x80)
    data[0x80:0x84] = b"PE\x00\x00"
    struct.pack_into("<H", data, 0x80 + 6, 1)
    struct.pack_into("<H", data, 0x80 + 20, 0)
    struct.pack_into("<II", data, 0x80 + 24 + 16, 0x100, 0x200)
    return bytes(data) + overlay


class InstallerTests(unittest.TestCase):
    def test_pe_offset(self):
        data = toy_pe(b"ISSetupStream\x00")
        self.assertEqual(installer.pe_overlay_offset(data), 0x300)

    def test_nibble_key_entry_round_trip(self):
        payload = bytes(i % 256 for i in range(3000))
        name = "RailwayPatch.msp"
        ciphertext = encrypt_entry(payload, name, flags=4)
        self.assertEqual(installer.decode_stream_entry(ciphertext, name, 4, False), payload)
        compressed = zlib.compress(payload)
        ciphertext = encrypt_entry(compressed, name)
        self.assertEqual(installer.decode_stream_entry(ciphertext, name, 0, True), payload)

    def test_msp_inside_installer(self):
        cfb = bytes.fromhex("d0cf11e0a1b11ae1") + b"RAILWAY_TEST"
        name = "RailwayPatch.msp"
        zipped = zlib.compress(cfb)
        cipher = encrypt_entry(zipped, name)
        nbytes = name.encode("utf-16le")
        record = (struct.pack("<ii", len(nbytes), 0) + b"\x00" * 2 +
                  struct.pack("<I", len(cipher)) + b"\x00" * 8 +
                  struct.pack("<H", 1) + b"\x00" * 24 + nbytes + cipher)
        head = (b"ISSetupStream\x00" + struct.pack("<HI", 1, 4)
                + b"\x00" * 8 + b"\x00" * 2 + b"\x00" * 16)
        with tempfile.TemporaryDirectory() as root:
            exe = Path(root) / "setup.exe"
            output = Path(root) / "result.msp"
            exe.write_bytes(toy_pe(head + record))
            result = installer.extract_msp(exe, output)
            self.assertEqual(output.read_bytes(), cfb)
            self.assertEqual(result["stream_count"], 1)

    def test_cfb_fat_stream(self):
        sector_size = 4096
        header = bytearray(sector_size)
        header[:8] = bytes.fromhex("d0cf11e0a1b11ae1")
        struct.pack_into("<H", header, 30, 12)  # 4096 bytes/sector
        struct.pack_into("<I", header, 44, 1)  # FAT sector count
        struct.pack_into("<I", header, 48, 1)  # directory starts at sector 1
        struct.pack_into("<I", header, 56, 4096)  # mini stream cutoff
        struct.pack_into("<I", header, 76, 0)  # FAT sector index
        fat = bytearray(sector_size)
        struct.pack_into("<III", fat, 0, 0xfffffffd, 0xfffffffe, 0xfffffffe)
        directory = bytearray(sector_size)
        label = "PCW_CAB_Family00".encode("utf-16le") + b"\x00\x00"
        directory[:len(label)] = label
        struct.pack_into("<H", directory, 64, len(label))
        directory[66] = 2
        struct.pack_into("<I", directory, 116, 2)
        struct.pack_into("<Q", directory, 120, sector_size)
        payload = b"MSCF" + b"\x00" * (sector_size - 4)
        with tempfile.TemporaryDirectory() as root:
            archive = Path(root) / "input.msp"
            output = Path(root) / "output.cab"
            archive.write_bytes(header + fat + directory + payload)
            result = installer.cfb_stream(archive, "PCW_CAB_Family00", output)
            self.assertEqual(result["bytes"], 4096)
            self.assertEqual(output.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
