#!/usr/bin/env python3
"""Redraw stretches of Taiwan's real railways from OpenStreetMap.

The app bundles the owner's Railway/ site's track_lines.geojson. The site
is no longer maintained, so where its line shapes are off the real track
the game corrects them here: osm_patches.json lists each stretch, the OSM
ways it was redrawn from and the new points. This script applies them to
the site's original file and writes the file the app bundles:

    python3 tools/real-railways/apply_osm_patches.py \\
        <railway-reference-private>/Railway/site_archive_clean/data/track_lines.geojson \\
        RailwayGameApp/Resources/RealRailways/track_lines.geojson

It refuses any base file but the one the patches were made against, and
any patch whose ends are not on the line it replaces. Standard library only.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

PATCHES = Path(__file__).with_name('osm_patches.json')
# How far a patch's end may be from the stretch it joins (metres).
JOIN_TOLERANCE_M = 0.5


def metres(a, b, c):
    """Distance from point c to segment a-b, all [lon, lat], in metres."""
    k = math.cos(math.radians(c[1]))
    ax, ay = a[0] * k * 111320, a[1] * 110574
    bx, by = b[0] * k * 111320, b[1] * 110574
    cx, cy = c[0] * k * 111320, c[1] * 110574
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0 if length == 0 else max(0, min(1, ((cx - ax) * dx + (cy - ay) * dy) / length))
    return math.hypot(cx - ax - t * dx, cy - ay - t * dy)


def main(base_path, out_path):
    spec = json.loads(PATCHES.read_text(encoding='utf-8'))
    raw = Path(base_path).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != spec['base']['sha256']:
        sys.exit(f'{base_path}: sha256 {digest}, expected {spec["base"]["sha256"]} ({spec["base"]["reference"]})')
    lines = json.loads(raw)
    by_key = {}
    for feature in lines['features']:
        by_key.setdefault(feature['properties']['lineKey'], []).append(feature)
    # Later stretches of a line first, so earlier vertex numbers still hold.
    for patch in sorted(spec['patches'], key=lambda p: (p['lineKey'], -p['afterVertex'])):
        features = by_key.get(patch['lineKey'], [])
        if len(features) != 1 or features[0]['geometry']['type'] != 'LineString':
            sys.exit(f'{patch["id"]}: {patch["lineKey"]} is not one line')
        coords = features[0]['geometry']['coordinates']
        after, before, points = patch['afterVertex'], patch['beforeVertex'], patch['points']
        if not 0 <= after < before < len(coords) or len(points) < 2:
            sys.exit(f'{patch["id"]}: vertices {after}..{before} not in a line of {len(coords)}')
        if metres(coords[after], coords[after + 1], points[0]) > JOIN_TOLERANCE_M:
            sys.exit(f'{patch["id"]}: does not start on segment {after}')
        if metres(coords[before - 1], coords[before], points[-1]) > JOIN_TOLERANCE_M:
            sys.exit(f'{patch["id"]}: does not end on segment {before - 1}')
        features[0]['geometry']['coordinates'] = coords[:after + 1] + points + coords[before:]
    text = json.dumps(lines, ensure_ascii=False, separators=(',', ':')) + '\n'
    Path(out_path).write_text(text, encoding='utf-8')
    print(f'{out_path}: {len(spec["patches"])} stretches redrawn from OpenStreetMap')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
