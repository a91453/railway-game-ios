"""A small GeoTIFF reader on the standard library alone, for measuring GHSL's
building heights (decision 386, the report's §8.2). It reads what GHSL's
tiles use and little else: one band, strips or tiles, no compression, LZW
or deflate, horizontal differencing, 8/16/32-bit integers or 32-bit floats,
either byte order (differencing only on unsigned samples), classic or
BigTIFF. The pixel grid comes from ModelPixelScale and
ModelTiepoint. Blocks are decoded when first read, and the last few kept.

    raster = Raster('tile.tif')
    raster.value(column, row)          # None outside the raster
    raster.at(x, y)                    # in the file's own coordinates
"""
import struct
import zlib
from array import array

TYPES = {1: 'B', 2: 'c', 3: 'H', 4: 'I', 5: 'II', 6: 'b', 8: 'h', 9: 'i', 11: 'f', 12: 'd', 16: 'Q'}
SIZES = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 8: 2, 9: 4, 11: 4, 12: 8, 16: 8}
SAMPLES = {(1, 8): 'B', (1, 16): 'H', (1, 32): 'I', (2, 8): 'b', (2, 16): 'h', (2, 32): 'i', (3, 32): 'f'}


def lzw(data):
    """TIFF's LZW: MSB-first codes of 9–12 bits, 256 clear, 257 end, with
    the early change (the width grows one code before the table fills)."""
    out = bytearray()
    table = [bytes([i]) for i in range(256)] + [b'', b'']
    width, bits, held, previous = 9, 0, 0, None
    for byte in data:
        held = (held << 8) | byte
        bits += 8
        while bits >= width:
            bits -= width
            code = (held >> bits) & ((1 << width) - 1)
            held &= (1 << bits) - 1
            if code == 256:
                table = table[:258]
                width, previous = 9, None
                continue
            if code == 257:
                return bytes(out)
            if previous is None:
                entry = table[code]
            elif code < len(table):
                entry = table[code]
                table.append(previous + entry[:1])
            else:
                entry = previous + previous[:1]
                table.append(entry)
            out += entry
            previous = entry
            if len(table) + 1 >= (1 << width) and width < 12:
                width += 1
    return bytes(out)


class Raster:
    def __init__(self, path, cache=64):
        self.file = open(path, 'rb')
        head = self.file.read(8)
        self.order = {b'II': '<', b'MM': '>'}[head[:2]]
        version = struct.unpack(self.order + 'H', head[2:4])[0]
        if version == 42:
            self.big, first = False, struct.unpack(self.order + 'I', head[4:8])[0]
        elif version == 43:
            self.big, first = True, struct.unpack(self.order + 'Q', self.file.read(8))[0]
        else:
            raise ValueError('not a TIFF')
        tags = self._tags(first)
        self.width, self.height = tags[256][0], tags[257][0]
        if tags.get(277, [1])[0] != 1:
            raise ValueError('only one band is read')
        bits = tags.get(258, [1])[0]
        self.sample = SAMPLES[(tags.get(339, [1])[0], bits)]
        self.size = bits // 8
        self.compression = tags.get(259, [1])[0]
        if self.compression not in (1, 5, 8, 32946):
            raise ValueError(f'compression {self.compression} is not read')
        self.predictor = tags.get(317, [1])[0]
        if self.predictor == 2 and not self.sample.isupper():
            raise ValueError('differencing is read only on unsigned samples')
        if self.predictor not in (1, 2):
            raise ValueError(f'predictor {self.predictor} is not read')
        if 322 in tags:
            self.block = (tags[322][0], tags[323][0])
            self.offsets, self.counts = tags[324], tags[325]
        else:
            self.block = (self.width, tags.get(278, [self.height])[0])
            self.offsets, self.counts = tags[273], tags[279]
        self.across = -(-self.width // self.block[0])
        scale, tie = tags.get(33550), tags.get(33922)
        self.scale = (scale[0], scale[1]) if scale else (1.0, 1.0)
        self.origin = (tie[3] - tie[0] * self.scale[0], tie[4] + tie[1] * self.scale[1]) if tie else (0.0, 0.0)
        self.nodata = float(tags[42113].rstrip('\0')) if 42113 in tags else None
        self.cache, self.blocks = cache, {}

    def _tags(self, offset):
        self.file.seek(offset)
        # BigTIFF: an 8-byte count, 20-byte entries, values up to 8 bytes inline.
        count_format, entry, inline_size, pointer = ('Q', 'HHQ8s', 8, 'Q') if self.big else ('H', 'HHI4s', 4, 'I')
        count = struct.unpack(self.order + count_format, self.file.read(struct.calcsize(count_format)))[0]
        size = struct.calcsize('<' + entry)
        entries = [struct.unpack(self.order + entry, self.file.read(size)) for _ in range(count)]
        tags = {}
        for tag, kind, n, inline in entries:
            length = SIZES[kind] * n
            raw = inline[:length] if length <= inline_size else \
                self._read(struct.unpack(self.order + pointer, inline)[0], length)
            if kind == 2:
                tags[tag] = raw.decode('latin-1')
            elif kind == 5:
                pairs = struct.unpack(self.order + f'{2 * n}I', raw)
                tags[tag] = [pairs[i] / pairs[i + 1] for i in range(0, 2 * n, 2)]
            else:
                tags[tag] = list(struct.unpack(self.order + f'{n}{TYPES[kind]}', raw))
        return tags

    def _read(self, offset, length):
        self.file.seek(offset)
        return self.file.read(length)

    def _decode(self, index):
        raw = self._read(self.offsets[index], self.counts[index])
        if self.compression == 5:
            raw = lzw(raw)
        elif self.compression in (8, 32946):
            raw = zlib.decompress(raw)
        width = self.block[0]
        values = array(self.sample)
        values.frombytes(raw[:len(raw) // self.size * self.size])
        if (self.order == '<') != (array('H', [1]).tobytes() == b'\x01\x00'):
            values.byteswap()
        if self.predictor == 2:
            mask = (1 << (8 * self.size)) - 1
            for start in range(0, len(values) - width + 1, width):
                for i in range(start + 1, start + width):
                    values[i] = (values[i] + values[i - 1]) & mask
        return values

    def value(self, column, row):
        if not (0 <= column < self.width and 0 <= row < self.height):
            return None
        bw, bh = self.block
        index = (row // bh) * self.across + column // bw
        values = self.blocks.get(index)
        if values is None:
            if len(self.blocks) >= self.cache:
                self.blocks.pop(next(iter(self.blocks)))
            values = self.blocks[index] = self._decode(index)
        at = (row % bh) * bw + column % bw
        if at >= len(values):
            return None
        v = values[at]
        return None if self.nodata is not None and v == self.nodata else v

    def at(self, x, y):
        return self.value(int((x - self.origin[0]) // self.scale[0]), int((self.origin[1] - y) // self.scale[1]))
