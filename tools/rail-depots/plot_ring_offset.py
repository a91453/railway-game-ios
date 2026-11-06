#!/usr/bin/env python3
"""Decision 612: the Kaohsiung Circular Light Rail's bought track drawn over
the real light rail's own tracks (the app's `rail_tracks.json`, from
OpenStreetMap, ODbL, decision 402), one panel per game dump, zoomed onto a
few stretches of the ring.

    KLRT_OFFSET=1 KLRT_OFFSET_DUMP=after.json swift test --skip-build \\
        --filter KaohsiungLightRailOffsetTests
    python3 -I tools/rail-depots/plot_ring_offset.py \\
        RailwayGameApp/Resources/RealRailways/rail_tracks.json out.png \\
        before.json after.json

A dump is a list of [latitude, longitude, metres off the nearest real track,
piece] (piece 0 the first track round, 1 the second, 2 and 3 the seam).
Grey: the real tracks (surface and bridge, Kaohsiung system); blue: the
game's first track; red: its second. Each panel's title gives the dump's
mean and largest offset.
"""
import json
import math
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Stretches to zoom onto: (name, latitude, longitude), 120 m across.
VIEWS = [
    ("Kaisyuan Rd / C24", 22.6292, 120.3229),
    ("Hamasen / C14", 22.6212, 120.2757),
    ("Love River bridge / C11", 22.6193, 120.2896),
    ("Depot junction / C37", 22.6060, 120.3251),
]
HALF = 60.0
METRE_LAT = 110_800.0


def real_tracks(path):
    data = json.load(open(path, encoding="utf-8"))
    system = data["systems"].index("krtc")
    tracks = []
    for way in data["ways"]:
        if way["system"] != system or way["kind"] == "t":
            continue
        p = way["points"]
        x, y = p[0], p[1]
        points = [(y / 1e6, x / 1e6)]
        for i in range(3, len(p), 3):
            x += p[i]
            y += p[i + 1]
            points.append((y / 1e6, x / 1e6))
        tracks.append(points)
    return tracks


def main(tracks_file, out, *dumps):
    tracks = real_tracks(tracks_file)
    rows = [json.load(open(d)) for d in dumps]
    fig, axes = plt.subplots(len(rows), len(VIEWS), figsize=(4 * len(VIEWS), 4 * len(rows)), squeeze=False)
    for r, (name, dump) in enumerate(zip(dumps, rows)):
        offsets = [p[2] for p in dump if p[3] in (0, 1)]
        label = f"{name.split('/')[-1]}: mean {sum(offsets) / len(offsets):.1f} m, most {max(offsets):.1f} m"
        for c, (view, lat0, lon0) in enumerate(VIEWS):
            ax = axes[r][c]
            metre_lon = METRE_LAT * math.cos(math.radians(lat0))

            def xy(lat, lon):
                return (lon - lon0) * metre_lon, (lat - lat0) * METRE_LAT

            for track in tracks:
                pts = [xy(*p) for p in track]
                ax.plot([p[0] for p in pts], [p[1] for p in pts], color="#999999", linewidth=5, alpha=0.6, solid_capstyle="round")
            for piece, colour in ((0, "#1f5fbf"), (1, "#c0392b"), (2, "#1f5fbf"), (3, "#c0392b")):
                pts = [xy(p[0], p[1]) for p in dump if p[3] == piece]
                pts = [p for p in pts if abs(p[0]) <= HALF * 1.5 and abs(p[1]) <= HALF * 1.5]
                ax.scatter([p[0] for p in pts], [p[1] for p in pts], s=3, color=colour)
            ax.set_xlim(-HALF, HALF)
            ax.set_ylim(-HALF, HALF)
            ax.set_aspect("equal")
            ax.set_title(f"{view}\n{label}", fontsize=8)
            ax.tick_params(labelsize=6)
    fig.tight_layout()
    fig.savefig(out, dpi=110)


if __name__ == "__main__":
    main(*sys.argv[1:])
