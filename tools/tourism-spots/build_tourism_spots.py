#!/usr/bin/env python3
"""Coordinates of the game's tourist attractions (ARCHITECTURE decision 174).

The spots are the ones in the owner's OpenWorld `destination-catalog.js`
(27 rows) a railway can reach, plus the hot springs and the Pingxi sky
lanterns the game adds. The catalog has no coordinates, so each spot is
looked up by name in the OpenStreetMap extract of Taiwan (osmtoday.com's
`asia/taiwan.pbf`, ODbL 1.0) among objects tagged `tourism`, `natural`,
`historic`, `leisure` or `place`, nearest to where the spot is known to be
(`approx`, within `RADIUS_KM`); if nothing matches, `approx` stays and
`source` says so.

Skipped on purpose (a railway cannot get there, or the place is invented):
s03 Penghu Qimei, s05 Matsu coast, s10 Lanyu, s13 Xiaoliuqiu, s14 Green
Island, s19 Kinmen Shuitou; s22 "Danhai light rail, future", s24 "Taipei
landmark 303, an original future landmark".

    pip install osmium
    curl -LO https://osmtoday.com/asia/taiwan.pbf
    python3 -I tools/tourism-spots/build_tourism_spots.py taiwan.pbf \
        tools/tourism-spots/taiwan_attractions.json

Stars are in hundredths (100 to 500). Kinds: coast, mountain, hotSpring, town.
"""
import json
import math
import sys

import osmium

RADIUS_KM = 12.0
CLASS_TAGS = ("tourism", "natural", "historic", "leisure", "place")

# id, Chinese name, English name, kind, stars, names to look for, approx (lat, lon)
SPOTS = [
    ("s01", "墾丁・小灣", "Kenting Xiaowan", "coast", 400, ["墾丁", "小灣", "Kenting"], (21.9437, 120.7890)),
    ("s02", "九份", "Jiufen", "town", 400, ["九份", "Jiufen"], (25.1090, 121.8440)),
    ("s04", "清水斷崖", "Qingshui Cliff", "mountain", 400, ["清水斷崖", "Qingshui Cliff"], (24.2200, 121.6720)),
    ("s06", "日月潭", "Sun Moon Lake", "mountain", 450, ["日月潭", "Sun Moon Lake"], (23.8586, 120.9150)),
    ("s07", "阿里山", "Alishan", "mountain", 450, ["阿里山", "Alishan"], (23.5100, 120.8030)),
    ("s08", "太魯閣", "Taroko", "mountain", 450, ["太魯閣", "Taroko"], (24.1590, 121.6215)),
    ("s09", "野柳", "Yehliu", "coast", 350, ["野柳", "Yehliu"], (25.2062, 121.6908)),
    ("s11", "合歡山", "Hehuanshan", "mountain", 350, ["合歡山", "Hehuan"], (24.1430, 121.2720)),
    ("s12", "高美濕地", "Gaomei Wetlands", "coast", 350, ["高美濕地", "Gaomei"], (24.3125, 120.5497)),
    ("s15", "池上伯朗大道", "Chishang Brown Avenue", "mountain", 300, ["伯朗大道", "池上", "Chishang"], (23.1220, 121.2240)),
    ("s16", "七星潭", "Qixingtan", "coast", 300, ["七星潭", "Qixingtan"], (24.0300, 121.6270)),
    ("s17", "陽明山擎天崗", "Qingtiangang", "mountain", 300, ["擎天崗", "Qingtiangang"], (25.1610, 121.5670)),
    ("s18", "清境", "Qingjing", "mountain", 350, ["清境", "Qingjing"], (24.0560, 121.1620)),
    ("s20", "玉山群峰", "Yushan", "mountain", 400, ["玉山", "Yushan", "Jade Mountain"], (23.4700, 120.9570)),
    ("s21", "遠雄海洋公園", "Farglory Ocean Park", "town", 300, ["遠雄海洋公園", "Farglory Ocean Park"], (23.9456, 121.6112)),
    ("s23", "陶朱隱園", "Taozhu Yinyuan", "town", 300, ["陶朱隱園"], (25.0386, 121.5462)),
    ("s25", "淡江大橋", "Tamsui River Bridge", "town", 250, [], (25.1744, 121.4310)),
    ("s26", "麗寶賽車場", "Lihpao Racing Park", "town", 250, ["麗寶", "Lihpao"], (24.3300, 120.6980)),
    ("s27", "Xpark・水族探索", "Xpark", "town", 350, ["Xpark", "青埔"], (25.0139, 121.1980)),
    ("h01", "北投溫泉", "Beitou Hot Springs", "hotSpring", 350, ["北投溫泉", "北投", "Beitou"], (25.1370, 121.5086)),
    ("h02", "烏來溫泉", "Wulai Hot Springs", "hotSpring", 350, ["烏來", "Wulai"], (24.8630, 121.5490)),
    ("h03", "礁溪溫泉", "Jiaoxi Hot Springs", "hotSpring", 350, ["礁溪", "Jiaoxi"], (24.6700, 121.7700)),
    ("h04", "關子嶺溫泉", "Guanziling Hot Springs", "hotSpring", 300, ["關子嶺", "Guanziling"], (23.3350, 120.5090)),
    ("h05", "四重溪溫泉", "Sichongxi Hot Springs", "hotSpring", 300, ["四重溪", "Sichongxi"], (22.0668, 120.7977)),
    ("p01", "平溪天燈", "Pingxi Sky Lanterns", "town", 350, ["十分", "平溪", "Shifen", "Pingxi"], (25.0415, 121.7745)),
]


def km(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((a[0] - b[0]) * 110.574, (a[1] - b[1]) * 111.320 * math.cos(lat))


def score(tags):
    """Higher is a better kind of object to put a spot on."""
    if tags.get("tourism") in ("attraction", "viewpoint", "theme_park", "zoo", "aquarium", "museum"):
        return 4
    if tags.get("natural") in ("peak", "water", "bay", "beach", "cliff", "hot_spring", "wetland"):
        return 3
    if any(k in tags for k in ("historic", "leisure")):
        return 2
    if tags.get("place") in ("village", "town", "suburb", "neighbourhood", "hamlet", "locality"):
        return 1
    return 0


class Finder(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.best = {}

    def consider(self, kind, oid, tags, lat, lon):
        if not any(k in tags for k in CLASS_TAGS):
            return
        names = " ".join(tags.get(k, "") for k in ("name", "name:zh", "name:en", "name:zh-Hant", "alt_name"))
        if not names:
            return
        quality = score(tags)
        if quality == 0:
            return
        for spot in SPOTS:
            if not any(word in names for word in spot[5]):
                continue
            distance = km((lat, lon), spot[6])
            if distance > RADIUS_KM:
                continue
            # A better class wins; within a class the nearer to where it is known to be.
            key = (-quality, distance)
            if spot[0] not in self.best or key < self.best[spot[0]][0]:
                self.best[spot[0]] = (key, lat, lon, f"{kind}/{oid}", names.strip()[:60])

    def node(self, n):
        if n.location.valid():
            self.consider("node", n.id, n.tags, n.location.lat, n.location.lon)

    def area(self, a):
        try:
            outer = next(iter(a.outer_rings()))
        except StopIteration:
            return
        lats = [p.lat for p in outer]
        lons = [p.lon for p in outer]
        self.consider("area", a.orig_id(), a.tags, sum(lats) / len(lats), sum(lons) / len(lons))


def main():
    source, target = sys.argv[1], sys.argv[2]
    finder = Finder()
    finder.apply_file(source, locations=True)
    spots = []
    for sid, name, english, kind, stars, _, approx in SPOTS:
        found = finder.best.get(sid)
        lat, lon, origin, matched = (found[1], found[2], found[3], found[4]) if found else (approx[0], approx[1], "approx", "")
        spots.append({
            "id": sid, "name": name, "englishName": english, "kind": kind, "stars": stars,
            "lat": round(lat, 5), "lon": round(lon, 5), "source": origin, "matched": matched,
        })
        print(f"{sid} {name:12} {origin:16} {lat:.5f} {lon:.5f}  {matched}")
    with open(target, "w", encoding="utf-8") as handle:
        json.dump({"license": "OpenStreetMap contributors, ODbL 1.0", "attractions": spots}, handle, ensure_ascii=False, indent=1)
        handle.write("\n")


if __name__ == "__main__":
    main()
