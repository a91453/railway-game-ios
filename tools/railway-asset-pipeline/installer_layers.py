#!/usr/bin/env python3
"""Read-only extraction of a Railway installer overlay and its embedded MSP/CAB.

This handles the *observed* PE32 + ISSetupStream + CFB/MSP archive variant.
It is not a general Windows installer, MSI/MSP or digital-signature parser.
The installer executable is never run. See README.md for validation steps.
"""
import argparse
import json
from pathlib import Path
import struct
import sys
import zlib


class ContainerError(ValueError):
    pass


def u16(data, offset):
    return struct.unpack_from("<H", data, offset)[0]


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def u64(data, offset):
    return struct.unpack_from("<Q", data, offset)[0]


def pe_overlay_offset(blob: bytes) -> int:
    if len(blob) < 256 or blob[:2] != b"MZ":
        raise ContainerError("Expected Windows PE32 MZ executable")
    pe = u32(blob, 0x3c)
    if pe + 24 > len(blob) or blob[pe:pe + 4] != b"PE\x00\x00":
        raise ContainerError("Invalid PE signature")
    sections = u16(blob, pe + 6)
    opt_size = u16(blob, pe + 20)
    section_table = pe + 24 + opt_size
    if not 1 <= sections <= 128 or section_table + 40 * sections > len(blob):
        raise ContainerError("Invalid section table")
    end = 0
    for index in range(sections):
        at = section_table + 40 * index
        size = u32(blob, at + 16)
        address = u32(blob, at + 20)
        end = max(end, address + size)
    if end >= len(blob):
        raise ContainerError("No valid installer overlay after PE sections")
    return end


def decode_stream_entry(cipher: bytes, name: str, flags: int, compressed: bool) -> bytes:
    seed = name.encode("utf-8")
    magic = bytes((0x13, 0x35, 0x86, 0x07))
    key = bytes(byte ^ magic[i % 4] for i, byte in enumerate(seed))
    if not key:
        raise ContainerError("Missing entry name/stream key")
    output = bytearray(len(cipher))
    for at, value in enumerate(cipher):
        i = at % 0x400 if flags & 4 else at
        rolled = ((value << 4) | (value >> 4)) & 0xff
        output[at] = (~(key[i % len(key)] ^ rolled)) & 0xff
    if not compressed:
        return bytes(output)
    try:
        return zlib.decompress(output)
    except zlib.error as exc:
        raise ContainerError("Unable to inflate installer entry " + name) from exc


def extract_msp(executable: Path, output: Path) -> dict:
    blob = executable.read_bytes()
    overlay = pe_overlay_offset(blob)
    signature = b"ISSetupStream\x00"
    if blob[overlay:overlay + len(signature)] != signature:
        raise ContainerError("Expected ISSetupStream at PE overlay start")
    pos = overlay + len(signature)
    count, version = struct.unpack_from("<HI", blob, pos)
    pos += 6 + 8 + 2 + 16
    rows = []
    for index in range(count):
        if pos + 28 > len(blob):
            raise ContainerError(f"Unexpected EOF in installer entry #{index}")
        name_size, flags = struct.unpack_from("<ii", blob, pos)
        pos += 8 + 2
        cipher_size = u32(blob, pos)
        pos += 4 + 8
        compressed = u16(blob, pos) == 1
        pos += 2
        if version > 3:
            pos += 24  # Original modification/creation/access FILETIME values.
        if not (2 <= name_size <= 2048) or name_size % 2:
            raise ContainerError("Invalid UTF-16 entry name length")
        if pos + name_size + cipher_size > len(blob):
            raise ContainerError("Truncated encrypted stream")
        name = blob[pos:pos + name_size].decode("utf-16le").rstrip("\x00")
        pos += name_size
        cipher = blob[pos:pos + cipher_size]
        pos += cipher_size
        rows.append(dict(name=name, bytes_encrypted=cipher_size, flags=flags,
                         compressed=compressed))
        if name.casefold().endswith(".msp"):
            result = decode_stream_entry(cipher, name, flags, compressed)
            if result[:8] != bytes.fromhex("d0cf11e0a1b11ae1"):
                raise ContainerError("Decoded MSP is not a CFB compound document")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(result)
            rows[-1]["bytes_decoded"] = len(result)
    if not output.is_file():
        raise ContainerError("No .msp entry found in installer overlay")
    return dict(pe_overlay=overlay, stream_count=count, version=version, entries=rows,
                extracted_msp=output.name, bytes=output.stat().st_size)


def cfb_stream(source: Path, stream_name: str, target: Path) -> dict:
    """Extract one *large* ordinary stream in a standard 4096-byte-sector CFB.

    Embedded streams below the mini-stream cutoff, extended DIFAT tables, and
    unconventional sector sizes are deliberately unsupported.
    """
    with source.open("rb") as file:
        header = file.read(512)
        if header[:8] != bytes.fromhex("d0cf11e0a1b11ae1"):
            raise ContainerError("Not a Compound File Binary document")
        sector_size = 1 << u16(header, 30)
        sector_count = u32(header, 44)
        first_dir = u32(header, 48)
        cutoff = u32(header, 56)
        if sector_size != 4096 or sector_count > 109 or sector_count < 1:
            raise ContainerError("Unsupported CFB sector size or extended DIFAT")
        all_sectors = [u32(header, 76 + i * 4) for i in range(sector_count)]
        if any(x >= 0xfffffffa for x in all_sectors):
            raise ContainerError("Invalid CFB FAT sector number")
        fat = []
        for sector in all_sectors:
            file.seek((sector + 1) * sector_size)
            data = file.read(sector_size)
            if len(data) != sector_size:
                raise ContainerError("Truncated FAT sector")
            fat.extend(struct.unpack("<" + "I" * (sector_size // 4), data))

        def walk(first, budget):
            seen = set()
            sector = first
            for _ in range(budget):
                if sector >= 0xfffffffa:
                    return
                if sector in seen or sector >= len(fat):
                    raise ContainerError("CFB FAT cycle or invalid sector")
                seen.add(sector)
                yield sector
                sector = fat[sector]
            raise ContainerError("CFB stream exceeds its sector budget")

        def read_sector(sector):
            file.seek((sector + 1) * sector_size)
            data = file.read(sector_size)
            if len(data) != sector_size:
                raise ContainerError("Truncated CFB sector")
            return data

        directory = bytearray()
        for sector in walk(first_dir, len(fat)):
            directory += read_sector(sector)
        selected = None
        for at in range(0, len(directory) - 127, 128):
            entry = directory[at:at + 128]
            namelen = u16(entry, 64)
            if not (2 <= namelen <= 64 and namelen % 2 == 0):
                continue
            label = entry[:namelen - 2].decode("utf-16le")
            if label != stream_name or entry[66] != 2:
                continue
            selected = dict(first_sector=u32(entry, 116), size=u64(entry, 120))
            break
        if selected is None:
            raise ContainerError("MSP stream not found: " + stream_name)
        total = selected["size"]
        if total < cutoff:
            raise ContainerError("Target uses unsupported CFB mini stream")
        target.parent.mkdir(parents=True, exist_ok=True)
        written = 0
        with target.open("wb") as dest:
            for sector in walk(selected["first_sector"], (total + sector_size - 1) // sector_size + 1):
                size = min(sector_size, total - written)
                if not size:
                    break
                dest.write(read_sector(sector)[:size])
                written += size
                if written == total:
                    break
        if written != total:
            target.unlink(missing_ok=True)
            raise ContainerError("CFB stream extracted with incorrect byte count")
    if target.open("rb").read(4) != b"MSCF":
        target.unlink(missing_ok=True)
        raise ContainerError("Extracted stream is not a CAB")
    return dict(stream=stream_name, bytes=written, cab=target.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, help="Local, purchased Windows installer binary")
    parser.add_argument("--out", required=True, help="Private workspace for intermediate files")
    parser.add_argument("--stream", default="PCW_CAB_Family00", help="CFB internal CAB stream name")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    msp = out / "RailwayPatch.msp"
    cab = out / "RailwayFamily.cab"
    try:
        first = extract_msp(Path(args.exe), msp)
        second = cfb_stream(msp, args.stream, cab)
    except (OSError, ContainerError, UnicodeError, ValueError, struct.error) as exc:
        print("Railway installer extraction: " + str(exc), file=sys.stderr)
        return 1
    manifest = dict(installer=Path(args.exe).name, extraction=first, embedded_stream=second)
    (out / "installer_layers.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"extracted MSP={first['bytes']} bytes; CAB={second['bytes']} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
