#!/usr/bin/env python3
"""The base map's glyphs (ARCHITECTURE decision 151): the 256-character
ranges of the fonts the game's style asks for (`BaseMapStyle.fonts`), as
MapLibre's signed-distance-field protobufs, for the app to bundle in
`Resources/BaseMap/fonts/<font>/<first>-<last>.pbf`.

    python3 tools/basemap/fetch_glyphs.py RailwayGameApp/Resources/BaseMap/fonts

They are OpenFreeMap's (the ones its styles use, OpenMapTiles' build of
Noto Sans, SIL Open Font License 1.1): the `Ci/` reference keeps three of
the same files (`Ci/reference_snapshot/external/openfreemap-tiles/fonts/`,
byte for byte the same).

MapLibre Native draws Chinese, kana and Hangul with the device's own font
(`allowsFixedWidthGlyphGeneration`, `build_basemap.drawn_on_device`) and
never asks for a range made only of those. Of the other ranges, the ones
the map's names use (`build_basemap.py` lists them) and their neighbours
are bundled whole (REAL, the bold font only for Latin); every other one is
an empty set of glyphs. MapLibre never lays out a tile's labels while a
range they need fails to load, so a name in an unexpected script must find
a file, even an empty one: it then shows without those characters rather
than leaving the whole tile without labels.
"""
import os
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_basemap import drawn_on_device  # noqa: E402

FONTS = ('Noto Sans Regular', 'Noto Sans Bold')
SERVER = 'https://tiles.openfreemap.org/fonts/{font}/{first}-{last}.pbf'
# Latin, its extensions and Greek; Latin Extended Additional; punctuation,
# letter-like symbols, arithmetic, box drawing and shapes, symbols; small
# and half/full-width forms.
REAL = {
    'Noto Sans Regular': (0, 256, 512, 768, 7680, 8192, 8448, 8704, 9472, 9728, 65024, 65280),
    'Noto Sans Bold': (0, 256, 8192),
}


def empty(font, first, last):
    """A glyphs protobuf with no glyphs: `glyphs { stacks { name, range } }`."""
    def field(number, payload):
        return bytes([number << 3 | 2]) + varint(len(payload)) + payload
    stack = field(1, font.encode()) + field(2, f'{first}-{last}'.encode())
    return field(1, stack)


def varint(v):
    out = bytearray()
    while v > 0x7F:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)


def main(out):
    real = empties = total = 0
    for font in FONTS:
        folder = os.path.join(out, font)
        os.makedirs(folder, exist_ok=True)
        for first in range(0, 65536, 256):
            last = first + 255
            if all(drawn_on_device(c) for c in range(first, last + 1)):
                continue
            if first in REAL[font]:
                url = SERVER.format(font=urllib.parse.quote(font), first=first, last=last)
                request = urllib.request.Request(url, headers={'User-Agent': 'railway-game-ios tools/basemap'})
                with urllib.request.urlopen(request) as response:
                    data = response.read()
                real += 1
            else:
                data = empty(font, first, last)
                empties += 1
            with open(os.path.join(folder, f'{first}-{last}.pbf'), 'wb') as f:
                f.write(data)
            total += len(data)
    print(f'{out}: {real} ranges of glyphs and {empties} empty ones, {total} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
