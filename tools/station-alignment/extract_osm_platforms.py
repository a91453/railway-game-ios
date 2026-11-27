#!/usr/bin/env python3
"""Station alignment (decision 1021): the real platforms and station buildings
of one OpenStreetMap extract, for StationAlignmentReportTests.

Reads a whole extract (osmtoday.com, as tools/real-world-population does) with
pyosmium and writes, as compact JSON:

- platforms: every way or multipolygon tagged railway=platform, or
  public_transport=platform for a train, subway, light rail, monorail or tram
  (not a bus stop): its OSM id, name, ref, mode tags, layer/level/location and
  outline (lat, lon), closed when it is an area;
- buildings: every building tagged building=train_station or
  building=transportation, or a building tagged railway=station or
  public_transport=station: its OSM id, name and outline.

Data: OpenStreetMap contributors, ODbL 1.0.

    python3 -I tools/station-alignment/extract_osm_platforms.py taiwan.pbf \
        tools/station-alignment/data/taiwan.json
"""
import json
import sys

import osmium

MODES = ("train", "subway", "light_rail", "monorail", "tram")
KEEP = ("name", "name:zh", "name:en", "name:ja", "ref", "railway", "public_transport", "layer", "level",
        "location", "covered", "building", "railway:platform", "local_ref") + MODES


def is_platform(tags):
    if tags.get("railway") == "platform":
        return True
    if tags.get("public_transport") == "platform":
        if tags.get("highway") == "bus_stop" or tags.get("bus") == "yes" and not any(tags.get(m) == "yes" for m in MODES):
            return False
        return any(tags.get(m) == "yes" for m in MODES)
    return False


def is_station_building(tags):
    building = tags.get("building")
    if not building:
        return False
    if building in ("train_station", "transportation"):
        return True
    return tags.get("railway") == "station" or tags.get("public_transport") == "station"


def keep(tags):
    return {k: tags[k] for k in KEEP if k in tags}


def ring(nodes):
    out = []
    for n in nodes:
        if not n.location.valid():
            return None
        out.append([round(n.location.lat, 6), round(n.location.lon, 6)])
    return out


class Handler(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.platforms = []
        self.buildings = []

    def way(self, w):
        tags = w.tags
        # Closed ways come again as areas; only open ones (a platform drawn
        # as a line) are taken here.
        if w.is_closed() or not is_platform(tags):
            return
        points = ring(w.nodes)
        if points and len(points) >= 2:
            self.platforms.append({"id": f"w{w.id}", "tags": keep(tags), "line": points})

    def area(self, a):
        tags = a.tags
        platform, building = is_platform(tags), is_station_building(tags)
        if not platform and not building:
            return
        oid = ("w" if a.from_way() else "r") + str(a.orig_id())
        rings = []
        for outer in a.outer_rings():
            points = ring(outer)
            if points and len(points) >= 3:
                rings.append(points[:-1] if points[0] == points[-1] else points)
        if not rings:
            return
        entry = {"id": oid, "tags": keep(tags), "rings": rings}
        (self.platforms if platform else self.buildings).append(entry)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    handler = Handler()
    handler.apply_file(sys.argv[1], locations=True)
    out = {
        "source": "OpenStreetMap contributors, " + sys.argv[1].rsplit("/", 1)[-1] + " (osmtoday.com)",
        "license": "ODbL 1.0 (https://www.openstreetmap.org/copyright)",
        "platforms": sorted(handler.platforms, key=lambda p: p["id"]),
        "buildings": sorted(handler.buildings, key=lambda b: b["id"]),
    }
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{sys.argv[2]}: {len(handler.platforms)} platforms, {len(handler.buildings)} buildings")


if __name__ == "__main__":
    main()
