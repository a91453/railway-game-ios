#!/usr/bin/env python3
"""Where the MTR's depots stand beside the lines on sale in Hong Kong
(decision 829), read from a whole OpenStreetMap extract of Hong Kong
(osmtoday.com's asia/china/hong_kong.pbf, ODbL) with pyosmium.

    python3 -I hk_depot_site.py hong_kong.pbf

prints what `RealLineDepotSite.siuHoWan` and `.wongChukHang` in
`Sources/GamePresentation/RealLineDepot.swift` are made from:

- Siu Ho Wan Depot (港鐵小蠔灣車廠, way 26321752), north of the Tung Chung
  Line between Sunny Bay and Tung Chung: the nodes where its leads leave
  the line (a `service=yard` way meeting a way of the line), how many of
  its yard tracks are 250 m or longer, and the middle of the near ends
  and of the far ends of its four long covered stabling tracks (ways
  453753728 to 453753731), the site's `yard`.
- Wong Chuk Hang Depot (黃竹坑車廠, way 454129803), under the podium south
  of Wong Chuk Hang station: OpenStreetMap maps the building, not the
  tracks inside it, so what is read is the building's outline (its
  corners furthest apart are the site's `yard`), the station and the
  third track on the viaduct east of it by which the real leads leave
  the line (ways 462266216, 648423547).
- Tseung Kwan O Depot (港鐵將軍澳車廠, way 28279911), which LOHAS Park
  station stands inside: printed for the record; the game lays no depot
  for the two trains of the LOHAS Park branch (decision 829).

The MTR publishes no track plan or stabling capacity of its depots
(`tools/hk-map/README.md`, 沒有的), so the game's sidings are as many as
the line's trains, one each, as the Taiwan depots' are.
"""
import math
import sys

import osmium

SIU_HO_WAN = 26321752
SIU_HO_WAN_SHED = [453753728, 453753729, 453753730, 453753731]
WONG_CHUK_HANG = 454129803
WONG_CHUK_HANG_LEADS = [462266216, 648423547]
TSEUNG_KWAN_O = 28279911
DEPOTS = {SIU_HO_WAN: "Siu Ho Wan", WONG_CHUK_HANG: "Wong Chuk Hang", TSEUNG_KWAN_O: "Tseung Kwan O"}
STATIONS = ["黃竹坑", "海洋公園", "欣澳", "東涌", "康城"]


def metres(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((a[0] - b[0]) * 111_320, (a[1] - b[1]) * 111_320 * k)


def inside(p, poly):
    x, y, c = p[1], p[0], False
    for i, a in enumerate(poly):
        b = poly[(i + 1) % len(poly)]
        if (a[0] > y) != (b[0] > y) and x < (b[1] - a[1]) * (y - a[0]) / (b[0] - a[0]) + a[1]:
            c = not c
    return c


def middle(points):
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def show(p):
    return f"({p[0]:.6f}, {p[1]:.6f})"


class Reader(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.outlines, self.rails, self.stations = {}, {}, []

    def way(self, w):
        tags = dict(w.tags)
        if w.id in DEPOTS:
            self.outlines[w.id] = [(n.lat, n.lon) for n in w.nodes]
        if tags.get("railway") in ("rail", "subway"):
            self.rails[w.id] = (tags, [(n.ref, n.lat, n.lon) for n in w.nodes])

    def node(self, n):
        tags = dict(n.tags)
        if tags.get("railway") == "station" and any(name in tags.get("name", "") for name in STATIONS):
            self.stations.append((tags["name"], (n.location.lat, n.location.lon)))


def main(path):
    reader = Reader()
    reader.apply_file(path, locations=True)
    for name, at in sorted(reader.stations):
        print(f"station {name}: {show(at)}")
    for depot, name in DEPOTS.items():
        outline = reader.outlines[depot]
        centre = middle(outline)
        print(f"\n{name} Depot, way {depot}: {len(outline)} nodes, centre {show(centre)}")
        far = max(((a, b) for a in outline for b in outline), key=lambda pair: metres(*pair))
        print(f"  corners furthest apart: {show(far[0])} and {show(far[1])}, {metres(*far):.0f} m")
        yard = []
        for way, (tags, nodes) in reader.rails.items():
            points = [(n[1], n[2]) for n in nodes]
            if tags.get("service") == "yard" and sum(inside(p, outline) for p in points) * 2 > len(points):
                yard.append((way, sum(metres(points[i], points[i + 1]) for i in range(len(points) - 1))))
        print(f"  yard tracks inside: {len(yard)}, of them 250 m or longer: {sum(1 for _, length in yard if length >= 250)}")
        # Where a yard track meets a track of the line, within 4 km.
        ways_at = {}
        for way, (tags, nodes) in reader.rails.items():
            if not any(metres((n[1], n[2]), centre) < 4_000 for n in nodes):
                continue
            for n in nodes:
                ways_at.setdefault(n[0], []).append((way, tags.get("service"), (n[1], n[2])))
        for node, ways in sorted(ways_at.items()):
            services = {w[1] for w in ways}
            if None in services and "yard" in services:
                print(f"  lead leaves the line at node {node} {show(ways[0][2])}, {metres(ways[0][2], centre):.0f} m from the centre,"
                      f" ways {sorted(w[0] for w in ways)}")
    shed = [[(n[1], n[2]) for n in reader.rails[way][1]] for way in SIU_HO_WAN_SHED]
    west, east = middle([min(t, key=lambda p: p[1]) for t in shed]), middle([max(t, key=lambda p: p[1]) for t in shed])
    print(f"\nSiu Ho Wan's covered stabling tracks {SIU_HO_WAN_SHED}: west ends' middle {show(west)}, east ends' middle {show(east)},"
          f" {metres(west, east):.0f} m")
    for way in WONG_CHUK_HANG_LEADS:
        nodes = reader.rails[way][1]
        print(f"Wong Chuk Hang lead, way {way}: {show(nodes[0][1:])} to {show(nodes[-1][1:])}")


if __name__ == "__main__":
    main(sys.argv[1])
