"""Freight railway, ports and cement/quarry works of Taiwan, from the whole
OSM extract (docs/research/FREIGHT_DEEPENING_2026-11-05.md §2).

Reads osmtoday.com's asia/taiwan.pbf with pyosmium (BSD 2-Clause, decision
93; CLAUDE.md: never Overpass) and the game's bundled
RailwayGameApp/Resources/RealRailways/tra.json for the stations. Prints:

1. track tagged as freight (`service=spur`, `usage=industrial`,
   `railway:traffic_mode=freight`) summed by the nearest TRA station;
2. named port, cement, oil, sugar and industrial lines, active
   (`railway=rail`) and historical (`disused`, `abandoned`, `razed`);
3. the nearest TRA station to each commercial port;
4. named cement works and quarries (`man_made=works`, `landuse=quarry`,
   `industrial=*`) and their nearest TRA station.

Research only: it writes nothing the game reads. OSM data is ODbL.

    python3 -I tools/freight-study/osm_freight_rail.py taiwan.pbf \
        RailwayGameApp/Resources/RealRailways/tra.json
"""

import collections
import json
import math
import sys

import osmium  # pyosmium: only for the extract.

# Ports: centroids of the TDX port polygons in the reference repository,
# Railway/geo-scene-reference-clean/source/public/geo/port_polygons.geojson
# (政府資料開放授權條款第 1 版). Taichung's polygon there covers only part of
# the harbour, so its centroid lies south of the port station.
PORTS = {
    "基隆港": (121.7526, 25.1460),
    "臺北港": (121.3791, 25.1459),
    "蘇澳港": (121.8686, 24.5946),
    "花蓮港": (121.6360, 23.9941),
    "臺中港": (120.4946, 24.2260),
    "安平港": (120.1700, 22.9738),
    "高雄港": (120.2977, 22.5836),
}
WORDS = ("港", "貨", "水泥", "泥", "砂", "石", "油", "煤", "鋼", "糖", "台塑", "台肥", "專用", "支線", "側線")
WORKS = ("水泥", "cement", "石礦", "礦", "煉", "中油", "refinery", "mine", "quarry")


def metres(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[1], a[0], b[1], b[0]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


class Freight(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.rail = []
        self.works = []

    def way(self, w):
        t = dict(w.tags)
        try:
            coords = [(n.lon, n.lat) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(coords) < 2:
            return
        railway = t.get("railway")
        name = t.get("name", "")
        if railway in ("rail", "disused", "abandoned", "razed"):
            freight = (
                t.get("service") == "spur"
                or t.get("usage") == "industrial"
                or t.get("railway:traffic_mode") == "freight"
            )
            if freight or any(word in name for word in WORDS):
                length = sum(metres(coords[i], coords[i + 1]) for i in range(len(coords) - 1))
                self.rail.append((railway, name, freight, length, coords[len(coords) // 2]))
        kind = " ".join(str(t.get(k, "")) for k in ("man_made", "landuse", "industrial", "product"))
        if name and (t.get("man_made") == "works" or t.get("landuse") == "quarry" or "industrial" in t):
            if any(word in name + kind for word in WORKS):
                xs = [c[0] for c in coords]
                ys = [c[1] for c in coords]
                self.works.append((name, (sum(xs) / len(xs), sum(ys) / len(ys))))


def main(pbf, tra_path):
    tra = json.load(open(tra_path, encoding="utf-8"))
    stations = {}
    for line in tra["lines"]:
        for s in line["stations"]:
            stations[s["name"]] = (s["lon"], s["lat"])

    def nearest(point):
        name = min(stations, key=lambda k: metres(point, stations[k]))
        return name, metres(point, stations[name]) / 1000

    handler = Freight()
    handler.apply_file(pbf, locations=True, idx="flex_mem")

    print("1. Active freight track (spur / industrial / freight yard) by nearest TRA station, within 6 km")
    by_station = collections.defaultdict(lambda: [0.0, set()])
    for railway, name, freight, length, middle in handler.rail:
        if railway != "rail" or not freight:
            continue
        station, km = nearest(middle)
        if km <= 6:
            by_station[station][0] += length
            if name:
                by_station[station][1].add(name)
    for station, (length, names) in sorted(by_station.items(), key=lambda kv: -kv[1][0]):
        print(f"   {station}\t{length / 1000:.2f} km\t{'、'.join(sorted(names))}")

    print("2. Named port, cement, oil and industrial lines (km)")
    named = collections.defaultdict(float)
    for railway, name, _, length, middle in handler.rail:
        if name and any(word in name for word in ("港", "貨", "泥", "油", "鋼", "台肥", "台塑", "工業區", "石渣", "石碴")):
            named[(railway, name)] += length
    for (railway, name), length in sorted(named.items(), key=lambda kv: (kv[0][0] != "rail", -kv[1])):
        print(f"   {railway}\t{name}\t{length / 1000:.2f}")

    print("3. Ports and their nearest TRA station")
    for port, point in PORTS.items():
        station, km = nearest(point)
        print(f"   {port}\t{station}\t{km:.1f} km")

    print("4. Cement works and quarries within 3 km of a TRA station")
    for name, point in sorted(handler.works):
        station, km = nearest(point)
        if km <= 3:
            print(f"   {name}\t{station}\t{km:.1f} km")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
