"""Tests of the small TIFF reader on made-up files (no network).

    python3 -I tools/overture-footprint-tiles/test_tiff.py
"""
import os
import struct
import sys
import tempfile
import unittest
import zlib
from array import array

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tiff import Raster, lzw  # noqa: E402


def lzw_encode(data):
    """TIFF LZW, the way writers do it: a clear code first, then the codes
    with the early width change, then the end code."""
    table = {bytes([i]): i for i in range(256)}
    width, codes, current = 9, [256], b''
    out_widths = [9]
    for byte in data:
        grown = current + bytes([byte])
        if grown in table:
            current = grown
            continue
        codes.append(table[current])
        out_widths.append(width)
        table[grown] = len(table) + 2
        # libtiff: one code ahead of the reader, so wider once the next
        # code no longer fits; a clear before the table reaches 4094.
        if len(table) + 2 >= 4094:
            codes.append(256)
            out_widths.append(width)
            table = {bytes([i]): i for i in range(256)}
            width = 9
        elif len(table) + 2 >= (1 << width):
            width += 1
        current = bytes([byte])
    codes.append(table[current])
    out_widths.append(width)
    codes.append(257)
    out_widths.append(width)
    held, bits, out = 0, 0, bytearray()
    for code, w in zip(codes, out_widths):
        held = (held << w) | code
        bits += w
        while bits >= 8:
            bits -= 8
            out.append((held >> bits) & 0xFF)
    if bits:
        out.append((held << (8 - bits)) & 0xFF)
    return bytes(out)


def write_tiff(path, values, width, height, order='<', compression=1, block=None, predictor=1,
               scale=(100.0, 100.0), origin=(1000.0, 5000.0), nodata=None, big=False):
    """A one-band uint16 GeoTIFF; `block` (w, h) makes it tiled, else one
    strip a row."""
    def encode(rows):
        raw = array('H', rows)
        if predictor == 2:
            w = block[0] if block else width
            raw = array('H', [(raw[i] - (raw[i - 1] if i % w else 0)) & 0xFFFF for i in range(len(raw))])
        if (order == '<') != (array('H', [1]).tobytes() == b'\x01\x00'):
            raw.byteswap()
        raw = raw.tobytes()
        return zlib.compress(raw) if compression == 8 else lzw_encode(raw) if compression == 5 else raw
    chunks = []
    if block:
        bw, bh = block
        for by in range(0, height, bh):
            for bx in range(0, width, bw):
                chunks.append(encode([values[y * width + x] if x < width and y < height else 0
                                      for y in range(by, by + bh) for x in range(bx, bx + bw)]))
    else:
        for y in range(height):
            chunks.append(encode(values[y * width:(y + 1) * width]))
    data, offsets, at = b'', [], 16 if big else 8
    for chunk in chunks:
        offsets.append(at + len(data))
        data += chunk
    extra = b''
    ifd_at = at + len(data)
    entries = []

    def tag(code, kind, items):
        nonlocal extra
        fmt = {3: 'H', 4: 'I', 12: 'd', 2: 's', 16: 'Q'}[kind]
        raw = items.encode() if kind == 2 else struct.pack(order + f'{len(items)}{fmt}', *items)
        count = len(raw) if kind == 2 else len(items)
        entries.append((code, kind, count, raw))
    tag(256, 4, [width])
    tag(257, 4, [height])
    tag(258, 3, [16])
    tag(259, 3, [compression])
    tag(277, 3, [1])
    tag(317, 3, [predictor])
    tag(339, 3, [1])
    if block:
        tag(322, 4, [block[0]])
        tag(323, 4, [block[1]])
        tag(324, 16 if big else 4, offsets)
        tag(325, 4, [len(c) for c in chunks])
    else:
        tag(273, 16 if big else 4, offsets)
        tag(278, 4, [1])
        tag(279, 4, [len(c) for c in chunks])
    tag(33550, 12, [scale[0], scale[1], 0.0])
    tag(33922, 12, [0.0, 0.0, 0.0, origin[0], origin[1], 0.0])
    if nodata is not None:
        tag(42113, 2, f'{nodata}\0')
    entries.sort()
    count_format, field, inline, pointer = ('Q', 'HHQ', 8, 'Q') if big else ('H', 'HHI', 4, 'I')
    tail_at = ifd_at + struct.calcsize('<' + count_format) + (inline + struct.calcsize('<' + field)) * len(entries) + inline
    ifd = struct.pack(order + count_format, len(entries))
    for code, kind, count, raw in entries:
        if len(raw) <= inline:
            ifd += struct.pack(order + field, code, kind, count) + raw.ljust(inline, b'\0')
        else:
            ifd += struct.pack(order + field + pointer, code, kind, count, tail_at + len(extra))
            extra += raw
    ifd += struct.pack(order + pointer, 0)
    marker = b'II' if order == '<' else b'MM'
    head = marker + (struct.pack(order + 'HHHQ', 43, 8, 0, ifd_at) if big else struct.pack(order + 'HI', 42, ifd_at))
    with open(path, 'wb') as file:
        file.write(head + data + ifd + extra)


class TiffTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.width, self.height = 37, 23
        self.values = [(x * 7 + y * 131) % 3000 for y in range(self.height) for x in range(self.width)]

    def check(self, **options):
        path = os.path.join(self.folder, 'a.tif')
        write_tiff(path, self.values, self.width, self.height, **options)
        raster = Raster(path)
        for y in range(self.height):
            for x in range(self.width):
                self.assertEqual(raster.value(x, y), self.values[y * self.width + x], (options, x, y))
        self.assertIsNone(raster.value(self.width, 0))
        self.assertIsNone(raster.value(0, -1))
        return raster

    def test_strips(self):
        for order in '<>':
            for compression in (1, 5, 8):
                self.check(order=order, compression=compression)

    def test_bigtiff(self):
        for order in '<>':
            self.check(order=order, compression=8, block=(16, 16), predictor=2, big=True)

    def test_tiles_with_differencing(self):
        for compression in (1, 5, 8):
            for predictor in (1, 2):
                self.check(compression=compression, block=(16, 16), predictor=predictor)

    def test_coordinates_and_nodata(self):
        self.values[0] = 65535
        path = os.path.join(self.folder, 'b.tif')
        write_tiff(path, self.values, self.width, self.height, nodata=65535)
        raster = Raster(path)
        self.assertIsNone(raster.value(0, 0))
        self.assertEqual(raster.at(1000.0 + 250, 5000.0 - 150), self.values[1 * self.width + 2])
        self.assertIsNone(raster.at(999.0, 5000.0))

    def test_lzw_long_run(self):
        data = bytes((i * i) % 251 for i in range(20000)) + bytes(5000)
        self.assertEqual(lzw(lzw_encode(data)), data)


if __name__ == '__main__':
    unittest.main()
