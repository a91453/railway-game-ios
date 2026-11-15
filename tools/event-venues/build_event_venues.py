#!/usr/bin/env python3
"""Coordinates of the game's event venues (decision 768, EVENT-VENUES).

The venues are the stadiums, arenas, concert halls and exhibition halls of
Taiwan and Hong Kong where the concerts, matches and exhibitions that bring
a station its crowds are held. Each is looked up by name in the
OpenStreetMap extracts (osmtoday.com's `asia/taiwan.pbf` and
`asia/china/hong_kong.pbf`, ODbL 1.0) among areas tagged as a stadium,
sports centre or hall, or an exhibition, events or concert venue, nearest to
where the venue is known to be (`approx`, within `RADIUS_KM`); the point is
the middle of its outline's bounding box. A venue nothing matches is left
out and said so (the Taichung International Exhibition Center, not yet
mapped in 2026-11, is not listed).

    pip install osmium
    curl -LO https://osmtoday.com/asia/taiwan.pbf
    curl -LO https://osmtoday.com/asia/china/hong_kong.pbf
    python3 -I tools/event-venues/build_event_venues.py taiwan.pbf hong_kong.pbf \
        tools/event-venues/event_venues.json

`seats` are the venues' usual capacities, rounded (concert seating where
it differs), from the venues' own pages: a weight for how often events are
held there, not a gameplay count of people.
"""
import json
import math
import sys

import osmium

RADIUS_KM = 3.0

# id, Chinese name, English name, kind, seats, names to look for, approx (lat, lon)
VENUES = [
    ("tw01", "臺北大巨蛋", "Taipei Dome", "stadium", 40000, ["臺北大巨蛋", "台北大巨蛋", "Taipei Dome"], (25.0438, 121.5603)),
    ("tw02", "臺北小巨蛋", "Taipei Arena", "arena", 15000, ["臺北小巨蛋", "台北小巨蛋", "Taipei Arena"], (25.0515, 121.5498)),
    ("tw03", "臺北田徑場", "Taipei Municipal Stadium", "stadium", 20000, ["臺北田徑場", "台北田徑場", "臺北市立田徑場", "Taipei Municipal Stadium"], (25.0487, 121.5520)),
    ("tw04", "天母棒球場", "Tianmu Baseball Stadium", "stadium", 10000, ["天母棒球場", "Tianmu Baseball"], (25.1149, 121.5332)),
    ("tw05", "臺北和平籃球館", "Taipei Heping Basketball Gymnasium", "arena", 7000, ["和平籃球館", "Heping Basketball"], (25.0213, 121.5460)),
    ("tw06", "臺北流行音樂中心", "Taipei Music Center", "arena", 5000, ["臺北流行音樂中心", "台北流行音樂中心", "Taipei Music Center"], (25.0518, 121.5990)),
    ("tw07", "新莊棒球場", "Xinzhuang Baseball Stadium", "stadium", 12000, ["新莊棒球場", "Xinzhuang Baseball"], (25.0405, 121.4500)),
    ("tw08", "新莊體育館", "Xinzhuang Gymnasium", "arena", 6500, ["新莊體育館", "Xinzhuang Gymnasium"], (25.0399, 121.4517)),
    ("tw09", "林口體育館", "Linkou Arena", "arena", 15000, ["體大林口綜合體育館", "林口體育館", "Linkou Arena"], (25.0346, 121.3835)),
    ("tw10", "桃園國際棒球場", "Taoyuan International Baseball Stadium", "stadium", 20000, ["樂天桃園棒球場", "桃園國際棒球場", "Taoyuan International Baseball"], (25.0005, 121.2005)),
    ("tw11", "桃園巨蛋", "Taoyuan Arena", "arena", 15000, ["桃園巨蛋", "桃園市立綜合體育館", "Taoyuan Arena"], (24.9945, 121.3235)),
    ("tw12", "新竹市立棒球場", "Hsinchu Baseball Stadium", "stadium", 10000, ["新竹市立棒球場", "新竹棒球場", "Hsinchu Baseball"], (24.8030, 120.9730)),
    ("tw13", "臺中洲際棒球場", "Taichung Intercontinental Baseball Stadium", "stadium", 20000, ["洲際棒球場", "Intercontinental Baseball"], (24.1985, 120.6855)),
    ("tw15", "斗六棒球場", "Douliu Baseball Stadium", "stadium", 15000, ["斗六棒球場", "Douliu Baseball"], (23.6950, 120.5280)),
    ("tw16", "臺南市立棒球場", "Tainan Municipal Baseball Stadium", "stadium", 11000, ["臺南市立棒球場", "台南市立棒球場", "Tainan Municipal Baseball"], (22.9855, 120.2090)),
    ("tw17", "澄清湖棒球場", "Chengcing Lake Baseball Stadium", "stadium", 20000, ["澄清湖棒球場", "Chengcing Lake Baseball"], (22.6537, 120.3524)),
    ("tw18", "國家體育場", "National Stadium", "stadium", 55000, ["國家體育場", "世運主場館", "National Stadium"], (22.7023, 120.2953)),
    ("tw19", "高雄巨蛋", "Kaohsiung Arena", "arena", 15000, ["高雄巨蛋", "高雄市立巨蛋", "Kaohsiung Arena"], (22.6692, 120.3025)),
    ("tw20", "高雄流行音樂中心", "Kaohsiung Music Center", "arena", 6000, ["高雄流行音樂中心", "Kaohsiung Music Center", "海音館"], (22.6205, 120.2910)),
    ("tw21", "南港展覽館", "Taipei Nangang Exhibition Center", "exhibitionHall", 30000, ["南港展覽館", "Nangang Exhibition"], (25.0567, 121.6175)),
    ("tw22", "臺北世貿中心展覽一館", "Taipei World Trade Center Exhibition Hall 1", "exhibitionHall", 20000, ["世貿一館", "世界貿易中心展覽", "世貿中心展覽一館", "Taipei World Trade Center"], (25.0336, 121.5611)),
    ("tw23", "高雄展覽館", "Kaohsiung Exhibition Center", "exhibitionHall", 20000, ["高雄展覽館", "Kaohsiung Exhibition"], (22.6075, 120.2985)),
    ("hk01", "啟德主場館", "Kai Tak Stadium", "stadium", 50000, ["啟德主場館", "Kai Tak Stadium"], (22.3240, 114.1980)),
    ("hk02", "啟德體藝館", "Kai Tak Arena", "arena", 10000, ["啟德體藝館", "Kai Tak Arena"], (22.3255, 114.1995)),
    ("hk03", "香港體育館", "Hong Kong Coliseum", "arena", 12500, ["香港體育館", "Hong Kong Coliseum"], (22.3015, 114.1820)),
    ("hk04", "香港大球場", "Hong Kong Stadium", "stadium", 40000, ["香港大球場", "Hong Kong Stadium"], (22.2770, 114.1920)),
    ("hk05", "伊利沙伯體育館", "Queen Elizabeth Stadium", "arena", 3500, ["伊利沙伯體育館", "Queen Elizabeth Stadium"], (22.2735, 114.1795)),
    ("hk06", "香港會議展覽中心", "Hong Kong Convention and Exhibition Centre", "exhibitionHall", 20000, ["香港會議展覽中心", "Hong Kong Convention and Exhibition Centre"], (22.2830, 114.1735)),
    ("hk07", "亞洲國際博覽館", "AsiaWorld-Expo", "exhibitionHall", 14000, ["亞洲國際博覽館", "AsiaWorld-Expo"], (22.3220, 113.9430)),
]

TAGS = {
    "leisure": {"stadium", "sports_centre", "sports_hall", "pitch", "track"},
    "building": {"stadium", "sports_hall", "sports_centre", "grandstand", "civic", "commercial", "yes", "public", "hall"},
    "amenity": {"exhibition_centre", "events_venue", "concert_hall", "conference_centre", "arts_centre", "theatre"},
}


def km(a, b):
    dlat = math.radians(b[0] - a[0])
    dlon = math.radians(b[1] - a[1]) * math.cos(math.radians((a[0] + b[0]) / 2))
    return 6371 * math.hypot(dlat, dlon)


class Areas(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.found = []

    def area(self, a):
        tags = a.tags
        if not any(tags.get(k) in v for k, v in TAGS.items()):
            return
        names = [tags.get(k) for k in ("name", "name:zh", "name:zh-Hant", "name:en", "alt_name", "official_name") if tags.get(k)]
        if not names:
            return
        lats, lons = [], []
        try:
            for ring in a.outer_rings():
                for n in ring:
                    lats.append(n.lat)
                    lons.append(n.lon)
        except osmium.InvalidLocationError:
            return
        if not lats:
            return
        # A way's outline counts its area, and a relation's; `area` comes from both.
        size = (max(lats) - min(lats)) * (max(lons) - min(lons))
        self.found.append((names, ((min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2), size,
                           f"{'way' if a.from_way() else 'relation'}/{a.orig_id()}"))


def main(paths, out):
    handler = Areas()
    for path in paths:
        handler.apply_file(path, locations=True)
    rows, missing = [], []
    for vid, name, english, kind, seats, look, approx in VENUES:
        best = None
        for names, point, size, ref in handler.found:
            if not any(any(w in n for w in look) for n in names):
                continue
            d = km(approx, point)
            if d > RADIUS_KM:
                continue
            # The largest outline of the name near where it is: the venue
            # itself, not its ticket office.
            if best is None or size > best[1]:
                best = (point, size, ref, names[0])
        if best is None:
            missing.append(vid)
            print(f"missing {vid} {name}", file=sys.stderr)
            continue
        rows.append({"id": vid, "name": name, "englishName": english, "kind": kind, "seats": seats,
                     "lat": round(best[0][0], 6), "lon": round(best[0][1], 6), "osm": best[2], "osmName": best[3]})
    json.dump({"source": "OpenStreetMap (osmtoday.com asia/taiwan.pbf, asia/china/hong_kong.pbf), ODbL 1.0, © OpenStreetMap contributors",
               "venues": rows, "missing": missing}, open(out, "w"), ensure_ascii=False, indent=1)
    print(f"{len(rows)} venues, {len(missing)} missing", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:-1], sys.argv[-1])
