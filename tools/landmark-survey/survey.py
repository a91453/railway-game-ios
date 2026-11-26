#!/usr/bin/env python3
"""Measure a landmark or natural spot from real data before it is modelled
(`.claude/skills/landmark-survey/SKILL.md`): its OpenStreetMap footprint,
parts, height tags, what stands round it, and the ground under it.

    python3 -I tools/landmark-survey/survey.py --pbf kyushu.pbf \\
        --lat 33.8845 --lon 130.8741 [--name 小倉城 | --osm way/153209407] \\
        [--radius 250] [--dem gsi|terrarium|none] [--tiles CACHE] --out DIR

Reads a whole OpenStreetMap extract with pyosmium (CLAUDE.md: osmtoday.com's
extracts, not Overpass; `pip install osmium numpy`), about forty seconds for
Kyushu's 355 MB; the slice it needs is kept as `DIR/osm-slice.json`, and
`--slice DIR/osm-slice.json` instead of `--pbf` reruns in a second.

Picks the landmark by `--osm`, else the building or historic area within
`--radius` whose name contains `--name`, else the building under the point.
Writes into DIR:

- `survey.json`: the footprint in metres (x east, y north, from the
  footprint's centre), its area, the smallest box round it (long side L,
  short side W, the long side's bearing from north), every OSM tag that
  says a size or a look (height, levels, roof, colour, material) with the
  element it came from, the `building:part`s inside it, the buildings it
  covers (those the game would clear) and the famous things round it (which
  the game must not clear), and, with `--dem`, the ground under the
  footprint (lowest, highest, mean) and round it.
- `plan.svg`: the footprint, its parts, the box, the neighbours, the famous
  things, the ground's contours, a 10 m scale and north.
- `survey.md`: the same as a table, each value with its source, and the
  lines still to be filled from a published plan, elevations and photos.

Ground: `gsi` is Japan's 国土地理院 elevation tiles (5 m from the laser
survey where there is one, else 10 m; licence 国土地理院コンテンツ利用規約,
credit 「国土地理院の標高タイルを加工して作成」); `terrarium` the
Terrarium tiles on AWS Open Data (Mapzen; SRTM, about 30 m outside the USA,
credits in https://github.com/tilezen/joerd/blob/master/docs/attribution.md).
Tiles are cached in `--tiles` (default DIR/tiles).

The way of working (measure first, record every fact's source, keep the
famous whole) follows the ideas of Pocket City's `fetch_osm.py`, `plot.py`
and `references/research.md` (April Zhu, PolyForm Noncommercial 1.0.0);
no code was taken from it: this is the project's own.
Map data (c) OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib

import numpy as np

LOOK_KEYS = ("height", "min_height", "building:levels", "building:min_level", "roof:levels", "roof:shape",
             "roof:height", "roof:colour", "roof:material", "roof:orientation", "roof:direction",
             "building:colour", "building:material", "colour", "material", "ele", "architect",
             "start_date", "heritage", "heritage:operator", "ref:jp:bunka", "wikidata", "wikipedia")
FAMOUS_KEYS = ("wikidata", "wikipedia", "heritage", "historic", "tourism", "ref:jp:bunka")
FAMOUS_TOURISM = {"attraction", "museum", "viewpoint", "artwork", "gallery", "zoo", "theme_park"}
# landuse, natural and leisure are left out: assembling every forest and
# field of an extract into areas takes minutes; the ground comes from --dem.
KINDS = ("building", "building:part", "historic", "tourism", "man_made", "bridge", "heritage", "wikidata")
STOREY = 3.2          # metres a storey when only the levels are mapped (an estimate, said so)
UA = "railway-game-landmark-survey/1.0"


# --- geometry ------------------------------------------------------------------

def to_local(points, lat0, lon0):
    pts = np.asarray(points, float)
    x = (pts[:, 1] - lon0) * 111320.0 * math.cos(math.radians(lat0))
    y = (pts[:, 0] - lat0) * 110574.0
    return np.stack([x, y], 1)


def area(ring):
    x, y = ring[:, 0], ring[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def centroid(ring):
    x, y = ring[:, 0], ring[:, 1]
    cross = x * np.roll(y, -1) - np.roll(x, -1) * y
    a = 0.5 * cross.sum()
    if abs(a) < 1e-9:
        return ring.mean(0)
    return np.array([((x + np.roll(x, -1)) * cross).sum(), ((y + np.roll(y, -1)) * cross).sum()]) / (6 * a)


def inside(point, ring):
    x, y = point
    hit = False
    for (x1, y1), (x2, y2) in zip(ring, np.roll(ring, -1, 0)):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def hull(points):
    pts = sorted(set(map(tuple, np.round(points, 4))))
    if len(pts) < 3:
        return np.array(pts)

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (p[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(p)
        return out
    return np.array(half(pts)[:-1] + half(pts[::-1])[:-1])


def box(points):
    """The smallest rectangle round `points`: long side, short side, the long side's bearing (0..180, from north)."""
    h = hull(points)
    best = None
    for a, b in zip(h, np.roll(h, -1, 0)):
        d = b - a
        if not d.any():
            continue
        u = d / np.linalg.norm(d)
        v = np.array([-u[1], u[0]])
        pu, pv = h @ u, h @ v
        size = (pu.max() - pu.min(), pv.max() - pv.min())
        if best is None or size[0] * size[1] < best[0]:
            centre = u * (pu.max() + pu.min()) / 2 + v * (pv.max() + pv.min()) / 2
            best = (size[0] * size[1], size, u, v, centre)
    _, (su, sv), u, v, centre = best
    long_axis = u if su >= sv else v
    bearing = math.degrees(math.atan2(long_axis[0], long_axis[1])) % 180
    corners = [centre + s * u * su / 2 + t * v * sv / 2 for s, t in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return {"L": round(max(su, sv), 2), "W": round(min(su, sv), 2), "bearing": round(bearing, 1),
            "corners": [[round(c[0], 2), round(c[1], 2)] for c in corners]}


# --- OpenStreetMap -------------------------------------------------------------

def read_extract(pbf, lat, lon, reach):
    import osmium
    dlat, dlon = reach / 110574.0, reach / (111320.0 * math.cos(math.radians(lat)))
    south, north, west, east = lat - dlat, lat + dlat, lon - dlon, lon + dlon
    found = []
    fp = osmium.FileProcessor(pbf).with_locations().with_areas().with_filter(osmium.filter.KeyFilter(*KINDS))
    near = max(dlat, dlon) + 0.05   # degrees: a first point farther than this cannot reach the slice

    def far(location):
        return not location.valid() or abs(location.lat - lat) > near or abs(location.lon - lon) > near

    for o in fp:
        try:
            if o.is_area():
                first = next(iter(o.outer_rings()), None)
                if first is None or far(first[0].location):
                    continue
            elif o.is_way():
                if far(o.nodes[0].location):
                    continue
            elif o.is_node() and far(o.location):
                continue
        except (osmium.InvalidLocationError, IndexError):
            continue
        tags = dict(o.tags)
        if o.is_area():
            rings = []
            for outer in o.outer_rings():
                rings.append([[n.lat, n.lon] for n in outer])
            if not rings:
                continue
            ref = ("way/" if o.from_way() else "relation/") + str(o.orig_id())
            geometry = {"type": "area", "rings": rings}
        elif o.is_way() and not o.is_closed():
            try:
                line = [[n.lat, n.lon] for n in o.nodes]
            except osmium.InvalidLocationError:
                continue
            ref, geometry = f"way/{o.id}", {"type": "line", "line": line}
        elif o.is_node():
            if not o.location.valid():
                continue
            ref, geometry = f"node/{o.id}", {"type": "point", "point": [o.location.lat, o.location.lon]}
        else:
            continue
        points = [p for ring in geometry.get("rings", [geometry.get("line") or [geometry.get("point")]]) for p in ring]
        if any(south <= p[0] <= north and west <= p[1] <= east for p in points):
            found.append({"ref": ref, "tags": tags, **geometry})
    return {"lat": lat, "lon": lon, "reach": reach, "read": time.strftime("%Y-%m-%d"),
            "source": os.path.basename(pbf), "elements": found}


def famous(tags, point=False):
    if point:   # a mapped point (a memorial stone, a sign) counts only with a record of its own
        return any(k in tags for k in ("wikidata", "wikipedia", "heritage", "ref:jp:bunka"))
    return any(k in tags for k in FAMOUS_KEYS if k not in ("tourism", "historic")) or \
        tags.get("tourism") in FAMOUS_TOURISM or ("historic" in tags and tags["historic"] not in ("yes", "no"))


def name_of(tags):
    return tags.get("name:ja") or tags.get("name:zh") or tags.get("name") or tags.get("name:en") or ""


def pick(elements, lat0, lon0, osm, name, radius):
    areas = [e for e in elements if e["type"] == "area"]
    if osm:
        for e in areas:
            if e["ref"] == osm:
                return e
        raise SystemExit(f"{osm} is not an area in the slice; make --radius larger or check the id")
    here = np.zeros(2)
    if name:
        named = []
        for e in areas:
            if not any(name in e["tags"].get(k, "") for k in e["tags"] if k == "name" or k.startswith("name:")):
                continue
            ring = to_local(e["rings"][0], lat0, lon0)
            d = float(np.linalg.norm(centroid(ring)))
            if d <= radius:
                building = "building" in e["tags"] or "building:part" in e["tags"]
                named.append((not building, d, e))
        if named:
            return min(named, key=lambda t: t[:2])[2]
        raise SystemExit(f"no area named like {name!r} within {radius} m")
    for e in areas:
        if "building" in e["tags"] and inside(here, to_local(e["rings"][0], lat0, lon0)):
            return e
    raise SystemExit("no building under the point; give --name or --osm")


# --- the ground ----------------------------------------------------------------

def png_rgb(data):
    """8-bit RGB or RGBA PNG to an (h, w, 3) array, with the standard library."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    at, idat, width = 8, b"", 0
    while at < len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            if depth != 8 or colour not in (2, 6):
                raise ValueError("only 8-bit RGB(A) PNG")
            channels = 3 if colour == 2 else 4
        elif kind == b"IDAT":
            idat += body
        at += 12 + length
    raw = zlib.decompress(idat)
    stride = width * channels
    out = np.zeros((height, stride), np.int32)
    prev = np.zeros(stride, np.int32)
    for row in range(height):
        f = raw[row * (stride + 1)]
        line = np.frombuffer(raw, np.uint8, stride, row * (stride + 1) + 1).astype(np.int32)
        if f == 0:
            cur = line
        elif f == 2:
            cur = (line + prev) & 255
        else:
            cur = np.zeros(stride, np.int32)
            for i in range(stride):
                a = cur[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                if f == 1:
                    p = a
                elif f == 3:
                    p = (a + b) >> 1
                else:
                    pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                    p = a if pa <= pb and pa <= pc else b if pb <= pc else c
                cur[i] = (line[i] + p) & 255
        out[row] = cur
        prev = cur
    return out.reshape(height, width, channels)[:, :, :3]


def fetch(url, path):
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read() or None
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60) as r:
            data = r.read()
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        data = b""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return data or None


DEMS = {
    "gsi": {"z": 15, "layers": [("dem5a_png", 15), ("dem5b_png", 15), ("dem5c_png", 15), ("dem_png", 14)],
            "url": "https://cyberjapandata.gsi.go.jp/xyz/{layer}/{z}/{x}/{y}.png",
            "credit": "国土地理院の標高タイルを加工して作成（国土地理院コンテンツ利用規約）"},
    "terrarium": {"z": 15, "layers": [("terrarium", 15)],
                  "url": "https://s3.amazonaws.com/elevation-tiles-prod/{layer}/{z}/{x}/{y}.png",
                  "credit": "Terrarium terrain tiles, AWS Open Data (Mapzen and its sources)"},
}


def decode(layer, rgb):
    r, g, b = rgb[..., 0].astype(np.int64), rgb[..., 1].astype(np.int64), rgb[..., 2].astype(np.int64)
    if layer == "terrarium":
        return (r * 256 + g + b / 256.0 - 32768).astype(float)
    x = (r << 16) + (g << 8) + b
    h = np.where(x < (1 << 23), x, x - (1 << 24)) * 0.01
    return np.where(x == (1 << 23), np.nan, h)


class Ground:
    def __init__(self, kind, cache):
        self.spec, self.cache, self.tiles, self.used = DEMS[kind], cache, {}, set()

    def _tile(self, layer, z, x, y):
        key = (layer, z, x, y)
        if key not in self.tiles:
            url = self.spec["url"].format(layer=layer, z=z, x=x, y=y)
            data = fetch(url, os.path.join(self.cache, f"{layer}_{z}_{x}_{y}.png"))
            self.tiles[key] = decode(layer, png_rgb(data)) if data else None
        return self.tiles[key]

    def height(self, lat, lon):
        for layer, z in self.spec["layers"]:
            n = 1 << z
            fx = (lon + 180) / 360 * n * 256
            fy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n * 256
            px, py = fx - 0.5, fy - 0.5
            x0, y0 = int(math.floor(px)), int(math.floor(py))
            values = []
            for dy in (0, 1):
                for dx in (0, 1):
                    gx, gy = x0 + dx, y0 + dy
                    t = self._tile(layer, z, gx // 256, gy // 256)
                    values.append(np.nan if t is None else t[gy % 256, gx % 256])
            if not any(math.isnan(v) for v in values):
                self.used.add(layer)
                tx, ty = px - x0, py - y0
                return (values[0] * (1 - tx) + values[1] * tx) * (1 - ty) + (values[2] * (1 - tx) + values[3] * tx) * ty
        return math.nan


def ground_under(ground, ring, lat0, lon0, step=2.0):
    lo, hi = ring.min(0), ring.max(0)
    samples = []
    for x in np.arange(lo[0] + step / 2, hi[0], step):
        for y in np.arange(lo[1] + step / 2, hi[1], step):
            if inside((x, y), ring):
                samples.append(ground.height(lat0 + y / 110574.0, lon0 + x / (111320.0 * math.cos(math.radians(lat0)))))
    for p in ring:
        samples.append(ground.height(lat0 + p[1] / 110574.0, lon0 + p[0] / (111320.0 * math.cos(math.radians(lat0)))))
    s = np.array([v for v in samples if not math.isnan(v)])
    if not len(s):
        return None
    return {"lowest": round(float(s.min()), 2), "highest": round(float(s.max()), 2), "mean": round(float(s.mean()), 2),
            "drop": round(float(s.max() - s.min()), 2), "samples": int(len(s))}


def ground_grid(ground, lat0, lon0, reach, step):
    xs = np.arange(-reach, reach + 1e-6, step)
    grid = np.array([[ground.height(lat0 + y / 110574.0, lon0 + x / (111320.0 * math.cos(math.radians(lat0))))
                      for x in xs] for y in xs])
    return xs, grid


# --- the plan ------------------------------------------------------------------

def contours(xs, grid, interval):
    """Marching squares: line segments of every `interval` metres."""
    segs = []
    if np.isnan(grid).all():
        return segs
    low, high = np.nanmin(grid), np.nanmax(grid)
    for level in np.arange(math.ceil(low / interval) * interval, high, interval):
        for i in range(len(xs) - 1):
            for j in range(len(xs) - 1):
                c = [(xs[j], xs[i], grid[i, j]), (xs[j + 1], xs[i], grid[i, j + 1]),
                     (xs[j + 1], xs[i + 1], grid[i + 1, j + 1]), (xs[j], xs[i + 1], grid[i + 1, j])]
                if any(math.isnan(v[2]) for v in c):
                    continue
                pts = []
                for a, b in zip(c, c[1:] + c[:1]):
                    if (a[2] < level) != (b[2] < level):
                        t = (level - a[2]) / (b[2] - a[2])
                        pts.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
                for k in range(0, len(pts) - 1, 2):
                    segs.append((pts[k], pts[k + 1]))
    return segs


def svg(path, survey, view):
    size, pad = 800, 30
    scale = (size - 2 * pad) / (2 * view)

    def p(x, y):
        return f"{pad + (x + view) * scale:.1f},{pad + (view - y) * scale:.1f}"

    def poly(ring, style):
        return f'<polygon points="{" ".join(p(*q) for q in ring)}" style="{style}"/>'
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" font-family="sans-serif" font-size="12">',
           f'<rect width="{size}" height="{size}" fill="#f6f4ee"/>']
    for a, b in survey.get("_contours", []):
        out.append(f'<line x1="{p(*a).split(",")[0]}" y1="{p(*a).split(",")[1]}" x2="{p(*b).split(",")[0]}" '
                   f'y2="{p(*b).split(",")[1]}" stroke="#c9b99a" stroke-width="0.8"/>')
    for n in survey["neighbours"]:
        out.append(poly(n["ring"], "fill:#d9d6cf;stroke:#9a978f;stroke-width:.6"))
    for n in survey["covers"]:
        out.append(poly(n["ring"], "fill:#f1c5b5;stroke:#c0634a;stroke-width:.8"))
    out.append(poly(survey["footprint"]["ring"], "fill:#f3d27a;stroke:#7a5a12;stroke-width:1.6"))
    for part in survey["parts"]:
        out.append(poly(part["ring"], "fill:none;stroke:#7a5a12;stroke-width:.8;stroke-dasharray:3 2"))
    out.append(poly(survey["footprint"]["box"]["corners"], "fill:none;stroke:#2b5fa8;stroke-width:1;stroke-dasharray:6 3"))
    for f in survey["famous"]:
        x, y = f["at"]
        if abs(x) <= view and abs(y) <= view:
            cx, cy = p(x, y).split(",")
            out.append(f'<circle cx="{cx}" cy="{cy}" r="4" fill="#c0392b"/>'
                       f'<text x="{float(cx) + 6}" y="{float(cy) + 4}" fill="#7b241c">{f["name"][:24]}</text>')
    b = survey["footprint"]["box"]
    out.append(f'<text x="{pad}" y="{size - 34}">{survey["name"]}  L {b["L"]} m × W {b["W"]} m, long side {b["bearing"]}° from north, '
               f'{survey["footprint"]["area"]} m²</text>')
    bar = 10 * scale
    out.append(f'<line x1="{pad}" y1="{size - 14}" x2="{pad + bar}" y2="{size - 14}" stroke="#000" stroke-width="2"/>'
               f'<text x="{pad + bar + 6}" y="{size - 10}">10 m</text>')
    out.append(f'<text x="{size - pad - 10}" y="{pad + 4}" font-size="16">N↑</text></svg>')
    with open(path, "w") as f:
        f.write("\n".join(out))


# --- the record ----------------------------------------------------------------

def walls(ring, lat0, lon0):
    """Each side of the footprint: its length and the way its outside faces (degrees from north)."""
    out = []
    for p, q in zip(ring, np.roll(ring, -1, 0)):
        d = q - p
        length = float(np.hypot(*d))
        if length < 0.05:
            continue
        # the ring runs counter-clockwise, so the outside is on the right of each side
        faces = math.degrees(math.atan2(d[1], -d[0])) % 360
        out.append({"from": [round(float(p[0]), 2), round(float(p[1]), 2)], "length": round(length, 2), "faces": round(faces, 1),
                    "from_latlon": [round(lat0 + float(p[1]) / 110574.0, 7),
                                    round(lon0 + float(p[0]) / (111320.0 * math.cos(math.radians(lat0))), 7)]})
    return out


def look_tags(element):
    return {k: {"value": v, "source": element["ref"]} for k, v in element["tags"].items() if k in LOOK_KEYS}


def height_of(tags, ref):
    if "height" in tags:
        try:
            return {"value": float(str(tags["height"]).split()[0]), "source": f"OSM {ref} height", "estimate": False}
        except ValueError:
            pass
    if "building:levels" in tags:
        try:
            levels = float(tags["building:levels"]) + float(tags.get("roof:levels", 0))
            return {"value": round(levels * STOREY, 1), "estimate": True,
                    "source": f"OSM {ref} building:levels {tags['building:levels']} × {STOREY} m（推估）"}
        except ValueError:
            pass
    return None


def markdown(survey):
    s = survey
    b = s["footprint"]["box"]
    rows = [("量", "值", "來源"),
            ("輪廓長 L × 寬 W", f"{b['L']} × {b['W']} m", f"OSM {s['ref']} 的輪廓（最小外接矩形）"),
            ("長邊方位", f"{b['bearing']}°（從北順時針）", f"OSM {s['ref']}"),
            ("輪廓面積", f"{s['footprint']['area']} m²", f"OSM {s['ref']}")]
    h = s.get("height")
    rows.append(("高度", f"{h['value']} m" + ("（推估）" if h["estimate"] else "") if h else "—",
                 h["source"] if h else "OSM 沒有：從立面圖或照片量"))
    for k, v in s["tags"].items():
        rows.append((f"`{k}`", v["value"], f"OSM {v['source']}"))
    g = s.get("ground")
    if g:
        rows.append(("輪廓下的地面", f"{g['lowest']}–{g['highest']} m（落差 {g['drop']} m）", s["dem_credit"]))
    lines = [f"# {s['name']}：實測紀錄", "",
             f"`survey.py` {s['read']} 從 {s['osm_source']} 量（OSM {s['ref']}，© OpenStreetMap contributors, ODbL）。"
             "下表每格都有來源；「還要補」一節由做的人照 landmark-survey skill 從平面圖、立面圖、照片補上，補的每一格也寫來源。", "",
             "| " + " | ".join(rows[0]) + " |", "| --- | --- | --- |"]
    lines += ["| " + " | ".join(str(c).replace("|", "／") for c in r) + " |" for r in rows[1:]]
    lines += ["", "## 輪廓的牆（逆時針；朝向是牆外側面對的方位，從北順時針）", "",
              "| 起點 (x, y) m | 長 m | 朝向 | 起點經緯度 |", "| --- | --- | --- | --- |"]
    for w in s["footprint"]["walls"]:
        ll = w["from_latlon"]
        lines.append(f"| ({w['from'][0]}, {w['from'][1]}) | {w['length']} | {w['faces']}° | {ll[0]}, {ll[1]} |")
    if s["parts"]:
        lines += ["", "## 分段（building:part）", "", "| OSM | 高度 | 最低 | 層數 | 屋頂 |", "| --- | --- | --- | --- | --- |"]
        for part in s["parts"]:
            t = part["tags"]
            lines.append(f"| {part['ref']} | {t.get('height', '—')} | {t.get('min_height', '—')} | "
                         f"{t.get('building:levels', '—')} | {t.get('roof:shape', '—')} |")
    lines += ["", "## 會被取代的建物（模型站到的）", ""]
    lines += [f"- {c['ref']} {c['name'] or '（無名）'}" for c in s["covers"]] or ["- 沒有"]
    lines += ["", "## 附近有名的（不能清掉、不能蓋到）", ""]
    lines += [f"- {f['ref']} {f['name']}（{f['why']}，離中心 {f['distance']} m）" for f in s["famous"]] or ["- 沒有"]
    lines += ["", "## 還要補（每格附來源）", "",
              "| 量 | 值 | 來源 |", "| --- | --- | --- |",
              "| 總高（地面到最高點） |  | 立面圖／官方資料 |",
              "| 各層（台基、各重屋頂、塔）的高度 |  | 立面圖或照片量（寫推估） |",
              "| 屋頂形式、重數、屋脊方向 |  | 照片 |",
              "| 屋頂主色 |  | 俯視照或航照（checklist 第 10 條） |",
              "| 牆、重點色 |  | 晴天照片 2–4 張 |",
              "| 認得出的 3–5 個特徵 |  | model-look §1 |",
              "| 照片：正面、另兩側、俯視 |  | Commons 或官方，寫作者與授權 |",
              "| 舊版有沒有同類模型 |  | 舊版目錄（先查，尺寸對 L×W×高） |", ""]
    return "\n".join(lines)


def survey(osm, lat, lon, osm_ref, name, radius, dem, tiles, out):
    lat0, lon0 = osm["lat"], osm["lon"]
    target = pick(osm["elements"], lat, lon, osm_ref, name, radius)
    ring_ll = target["rings"][0]
    ring0 = to_local(ring_ll, lat0, lon0)
    c = centroid(ring0)
    # re-centre on the footprint
    lat0 += c[1] / 110574.0
    lon0 += c[0] / (111320.0 * math.cos(math.radians(lat0)))

    def local(ll):
        return to_local(ll, lat0, lon0)
    ring = local(ring_ll)
    if area(ring) < 0:
        ring = ring[::-1]
    if np.allclose(ring[0], ring[-1]):
        ring = ring[:-1]
    result = {"name": name_of(target["tags"]) or target["ref"], "ref": target["ref"], "read": osm["read"],
              "osm_source": osm["source"], "centre": {"lat": round(lat0, 7), "lon": round(lon0, 7)},
              "footprint": {"ring": np.round(ring, 2).tolist(), "area": round(area(ring), 1), "box": box(ring),
                            "walls": walls(ring, lat0, lon0)},
              "tags": look_tags(target), "height": height_of(target["tags"], target["ref"]),
              "parts": [], "covers": [], "neighbours": [], "famous": []}
    for e in osm["elements"]:
        if e["ref"] == target["ref"]:
            continue
        tags = e["tags"]
        if e["type"] == "area":
            r = local(e["rings"][0])
            mid = centroid(r)
            if "building:part" in tags and inside(mid, ring):
                result["parts"].append({"ref": e["ref"], "tags": {k: v for k, v in tags.items() if k in LOOK_KEYS},
                                        "ring": np.round(r, 2).tolist(), "height": height_of(tags, e["ref"])})
            elif "building" in tags:
                entry = {"ref": e["ref"], "name": name_of(tags), "ring": np.round(r, 2).tolist()}
                if inside(mid, ring):
                    result["covers"].append(entry)
                elif np.abs(r).max() < radius:
                    result["neighbours"].append(entry)
            at = mid
        elif e["type"] == "line":
            at = local(e["line"]).mean(0)
        else:
            at = local([e["point"]])[0]
        d = float(np.linalg.norm(at))
        if famous(tags, e["type"] == "point") and name_of(tags) and d <= radius:
            why = ", ".join(f"{k}={tags[k]}" for k in FAMOUS_KEYS if k in tags)
            result["famous"].append({"ref": e["ref"], "name": name_of(tags), "why": why, "distance": round(d),
                                     "at": [round(float(at[0]), 1), round(float(at[1]), 1)]})
    result["famous"].sort(key=lambda f: f["distance"])
    view = max(60.0, float(np.abs(ring).max()) * 2.2)
    if dem != "none":
        ground = Ground(dem, tiles or os.path.join(out, "tiles"))
        result["ground"] = ground_under(ground, ring, lat0, lon0)
        xs, grid = ground_grid(ground, lat0, lon0, view, max(2.0, view / 40))
        around = grid[~np.isnan(grid)]
        if len(around):
            result["ground_around"] = {"reach": round(view), "lowest": round(float(around.min()), 1),
                                       "highest": round(float(around.max()), 1)}
        result["dem_credit"] = DEMS[dem]["credit"] + "；用到 " + ", ".join(sorted(ground.used))
        drop = float(np.nanmax(grid) - np.nanmin(grid)) if len(around) else 0
        result["_contours"] = contours(xs, grid, 1.0 if drop < 15 else 2.0 if drop < 40 else 5.0)
    os.makedirs(out, exist_ok=True)
    svg(os.path.join(out, "plan.svg"), result, view)
    result.pop("_contours", None)
    with open(os.path.join(out, "survey.json"), "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, "survey.md"), "w") as f:
        f.write(markdown(result))
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pbf", help="an OpenStreetMap extract (.pbf)")
    ap.add_argument("--slice", help="osm-slice.json from an earlier run, instead of --pbf")
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lon", type=float)
    ap.add_argument("--osm", help="way/<id> or relation/<id> of the landmark")
    ap.add_argument("--name", help="part of the landmark's name")
    ap.add_argument("--radius", type=float, default=250, help="metres round the point to look (default 250)")
    ap.add_argument("--dem", choices=sorted(DEMS) + ["none"], default="none")
    ap.add_argument("--tiles", help="folder caching the elevation tiles (default OUT/tiles)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    if a.slice:
        with open(a.slice) as f:
            osm = json.load(f)
        lat = a.lat if a.lat is not None else osm["lat"]
        lon = a.lon if a.lon is not None else osm["lon"]
    else:
        if not a.pbf or a.lat is None or a.lon is None:
            ap.error("give --pbf with --lat and --lon, or --slice")
        lat, lon = a.lat, a.lon
        osm = read_extract(a.pbf, lat, lon, a.radius * 1.5)
        os.makedirs(a.out, exist_ok=True)
        with open(os.path.join(a.out, "osm-slice.json"), "w") as f:
            json.dump(osm, f, ensure_ascii=False)
    r = survey(osm, lat, lon, a.osm, a.name, a.radius, a.dem, a.tiles, a.out)
    b = r["footprint"]["box"]
    h = r["height"]
    g = r.get("ground")
    print(f"{r['name']} ({r['ref']}): L {b['L']} × W {b['W']} m, {r['footprint']['area']} m², "
          f"height {h['value'] if h else '—'}{' (estimate)' if h and h['estimate'] else ''}; "
          f"{len(r['parts'])} parts, covers {len(r['covers'])}, {len(r['famous'])} famous within {a.radius:.0f} m"
          + (f"; ground {g['lowest']}–{g['highest']} m" if g else ""))


if __name__ == "__main__":
    sys.exit(main())
