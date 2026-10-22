#!/usr/bin/env python3
"""Taiwan's temples for the 3D map's landmarks (decision 331).

Reads the geo-scene reference's temple tiles
(`Railway/geo-scene-reference-clean/source/public/religion/temples.pmtiles`
in a91453/railway-reference-private: the Ministry of the Interior's temple
registry, OpenStreetMap's places of worship and the Bureau of Cultural
Heritage's monuments, 19,201 points) and writes
`RailwayGameApp/Resources/BaseMap/taiwan_temples.json`, which
`GamePresentation`'s `RealTemples` reads.

    python3 -I tools/temples/build_temples.py temples.pmtiles \
        RailwayGameApp/Resources/BaseMap/taiwan_temples.json

Only the place and a size are kept: no name, address or deity. A temple
is `2` (large) when it is one of the hundred religious events' temples or
a listed monument, `0` (small) when it is a Tudigong shrine, else `1`.
The standard library only: the PMTiles directory and the vector tiles'
protocol buffers are read by hand.
"""

import gzip
import json
import math
import struct
import sys


def varint(data, at):
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return value, at


def decompress(data, compression):
    return gzip.decompress(data) if compression == 2 else data


def directory(data):
    """A PMTiles v3 directory's (tile id, run length, length, offset)."""
    count, at = varint(data, 0)
    ids, runs, lengths, offsets = [], [], [], []
    last = 0
    for _ in range(count):
        delta, at = varint(data, at)
        last += delta
        ids.append(last)
    for values in (runs, lengths):
        for _ in range(count):
            value, at = varint(data, at)
            values.append(value)
    for k in range(count):
        value, at = varint(data, at)
        offsets.append(offsets[k - 1] + lengths[k - 1] if value == 0 and k > 0 else value - 1)
    return list(zip(ids, runs, lengths, offsets))


def tiles(data):
    """Every tile's (id, start, length) and the header's compressions."""
    if data[:7] != b"PMTiles" or data[7] != 3:
        sys.exit("Not a PMTiles v3 file.")
    root_offset, root_length, _, _, leaf_offset, _, data_offset = struct.unpack_from("<7Q", data, 8)
    internal, tile_compression = data[97], data[98]
    found = []

    def walk(offset, length):
        for tile_id, run, size, start in directory(decompress(data[offset:offset + length], internal)):
            if run == 0:
                walk(leaf_offset + start, size)
            else:
                found.extend((tile_id + k, data_offset + start, size) for k in range(run))

    walk(root_offset, root_length)
    return found, tile_compression


def zxy(tile_id):
    """A Hilbert tile id's zoom, x and y (the PMTiles specification)."""
    first = 0
    for zoom in range(32):
        count = 1 << (2 * zoom)
        if first + count > tile_id:
            position, side = tile_id - first, 1 << zoom
            x = y = 0
            s = 1
            while s < side:
                rx = 1 & (position // 2)
                ry = 1 & (position ^ rx)
                if ry == 0:
                    if rx == 1:
                        x, y = s - 1 - x, s - 1 - y
                    x, y = y, x
                x += s * rx
                y += s * ry
                position //= 4
                s *= 2
            return zoom, x, y
        first += count
    sys.exit("A tile id out of range.")


def fields(message):
    at = 0
    while at < len(message):
        key, at = varint(message, at)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, at = varint(message, at)
        elif wire == 2:
            size, at = varint(message, at)
            value, at = message[at:at + size], at + size
        elif wire == 1:
            value, at = message[at:at + 8], at + 8
        elif wire == 5:
            value, at = message[at:at + 4], at + 4
        else:
            sys.exit("An unknown protocol buffer wire type.")
        yield number, value


def value_of(message):
    for number, value in fields(message):
        if number == 1:
            return value.decode()
        if number in (4, 5, 6):
            return value
        if number == 7:
            return bool(value)
        if number == 2:
            return struct.unpack("<f", value)[0]
        if number == 3:
            return struct.unpack("<d", value)[0]
    return None


def points(tile):
    """Each point feature's properties and first point, in tile units."""
    for number, layer in fields(tile):
        if number != 3:
            continue
        keys, values, features, extent = [], [], [], 4096
        for field, value in fields(layer):
            if field == 2:
                features.append(value)
            elif field == 3:
                keys.append(value.decode())
            elif field == 4:
                values.append(value_of(value))
            elif field == 5:
                extent = value
        for feature in features:
            tags, geometry = [], []
            for field, value in fields(feature):
                if field in (2, 4):
                    at, numbers = 0, []
                    while at < len(value):
                        number_, at = varint(value, at)
                        numbers.append(number_)
                    if field == 2:
                        tags = numbers
                    else:
                        geometry = numbers
            if len(geometry) < 3 or geometry[0] & 7 != 1:
                continue
            x = (geometry[1] >> 1) ^ -(geometry[1] & 1)
            y = (geometry[2] >> 1) ^ -(geometry[2] & 1)
            properties = {keys[tags[k]]: values[tags[k + 1]] for k in range(0, len(tags), 2)}
            yield properties, x, y, extent


def size(properties):
    if properties.get("is_top100") or properties.get("heritage_flag"):
        return 2
    if properties.get("deity_family") == "tudi":
        return 0
    return 1


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = open(sys.argv[1], "rb").read()
    found, compression = tiles(data)
    deepest = max(zxy(tile_id)[0] for tile_id, _, _ in found)
    temples, sources = {}, {}
    for tile_id, start, length in found:
        zoom, column, row = zxy(tile_id)
        if zoom != deepest:
            continue
        for properties, x, y, extent in points(decompress(data[start:start + length], compression)):
            # A point in a neighbour's buffer is that tile's.
            if not (0 <= x < extent and 0 <= y < extent):
                continue
            longitude = (column + x / extent) / (1 << zoom) * 360 - 180
            n = math.pi - 2 * math.pi * (row + y / extent) / (1 << zoom)
            latitude = math.degrees(math.atan(math.sinh(n)))
            key = properties["entity_id"]
            temples[key] = (round(latitude * 1e5), round(longitude * 1e5), size(properties))
            sources[key] = properties.get("source", "")
    rows = sorted(temples.values())
    counts = {}
    for source in sources.values():
        counts[source] = counts.get(source, 0) + 1
    out = {
        "source": "geo-scene reference temples.pmtiles: MOI temple registry, OpenStreetMap (ODbL 1.0), Bureau of Cultural Heritage",
        "sources": dict(sorted(counts.items())),
        # Each temple: latitude and longitude in 1e-5 degrees, then its size.
        "temples": [value for row in rows for value in row],
    }
    with open(sys.argv[2], "w") as file:
        json.dump(out, file, ensure_ascii=False, separators=(",", ":"))
        file.write("\n")
    sizes = [row[2] for row in rows]
    print(f"{len(rows)} temples: {sizes.count(2)} large, {sizes.count(1)} temples, {sizes.count(0)} small; {counts}")


if __name__ == "__main__":
    main()
