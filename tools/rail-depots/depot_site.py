#!/usr/bin/env python3
"""Where a real depot's leads leave its line and where its yard runs
(decision 479), read from a whole OpenStreetMap extract of Taiwan
(osmtoday.com's asia/taiwan.pbf, ODbL) with pyosmium.

    python3 -I depot_site.py taiwan.pbf

prints, for the Sanxia depot (三峽機廠) of the New Taipei Metro's Sanying
Line, the numbers `RealLineDepotSite.sanxia` in
`Sources/GamePresentation/RealLineDepot.swift` holds: the middle of the
crossover its leads leave the line by, the middle of its sidings' near
ends and of their far ends, and the real platforms' length (the game's
are not set from it: see the decision).

Decision 489: then, for the Danhai depot (淡海機廠, way 651032395) of the Danhai Light
Rail past Kanding, the numbers `RealLineDepotSite.danhai` holds: the
middle of the line's two tracks' ends, where its leads begin, and the
middle of its yard tracks' near (east) ends and of their far (west) ends.

Decision 535 (PR W): then, for the Wenhu Line's two depots, both past an
end as Danhai's is, the numbers `RealLineDepotSite.muzha` and `.neihu`
hold: the middle of the line's two tracks' ends past the end station,
where the leads begin, and the middle of the yard tracks' near ends (the
leads') and of their far ends.

Decision 535 (continued, ANKENGDEPOT): then, for the Ankeng depot
(安坑機廠, way 724086719) of the Ankeng LRT past Shuangcheng, what
`RealLineDepotSite.ankeng` is made from: the middle of the crossover past
the station the game's lead leaves at, the middle of the stabling tracks'
north ends, and the depot's northernmost node (the yard's far end is set
some 60 m east of it: see the site's comment), with the line's two tracks'
end past the station, where the real leads begin, and the stabling tracks'
south ends for comparison.
"""
import math
import sys

import osmium

DEPOT = 619043484           # landuse=railway, 三峽機廠
CROSSOVER = 1156270818      # service=crossover, the leads' junction
SIDINGS = [1136774767, 1136774768]
PLATFORM_FIRST = 1569306500  # the line's platforms, mapped together

DANHAI_ENDS = [605463606, 658195694]  # the line's two tracks past Kanding
# The yard tracks through its shed (railway=rail, building_passage); not the
# leads (690355134) nor the test track (690355136).
DANHAI_YARD = [690355135, 690355138, 690355139, 690355140, 690355141, 690355144,
               690355145, 690355204, 690377821, 690377824, 690377825]

# Decision 535: the Wenhu Line. Past Taipei Zoo its two tracks (ways
# 194634022, 194633990) end where the Muzha depot's leads (307449195,
# 307449196) begin; its stabling tracks are the three through the yard's
# west end (71380030, 71380035, 71380037).
MUZHA_ENDS = [194634022, 194633990]
MUZHA_YARD = [71380030, 71380035, 71380037]
MUZHA_LEADS = [307449195, 307449196]
# Past Taipei Nangang Exhibition Center its two tracks (310746644,
# 310746645) end where the Neihu depot's leads (499750991, 127958010)
# begin; its stabling tracks fan out north-west from the leads (499756245
# to 499756259).
NEIHU_ENDS = [310746644, 310746645]
NEIHU_YARD = list(range(499756245, 499756260))
NEIHU_LEADS = [499750991, 127958010]


# Decision 535 (continued): the Ankeng LRT. Past Shuangcheng its two tracks
# (1140796056, 1140796057) end where the real leads loop round into the
# depot from its north; the crossovers past the station (1137758430,
# 1137758431); the stabling tracks, two groups side by side (1140796066 to
# 1140796072, 1140796074 to 1140796078).
ANKENG_DEPOT = 724086719
ANKENG_ENDS = [1140796056, 1140796057]
ANKENG_CROSSOVER = [1137758430, 1137758431]
ANKENG_YARD = [*range(1140796066, 1140796073), *range(1140796074, 1140796079)]


class Ways(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = {}
        self.platforms = []

    def way(self, w):
        if w.id in (DEPOT, CROSSOVER, *SIDINGS, *DANHAI_ENDS, *DANHAI_YARD, *MUZHA_ENDS, *MUZHA_YARD, *MUZHA_LEADS, *NEIHU_ENDS, *NEIHU_YARD, *NEIHU_LEADS,
                    ANKENG_DEPOT, *ANKENG_ENDS, *ANKENG_CROSSOVER, *ANKENG_YARD):
            self.ways[w.id] = [(n.lat, n.lon) for n in w.nodes]
        elif w.id >= PLATFORM_FIRST and w.tags.get("railway") == "platform" and w.tags.get("area") == "yes":
            points = [(n.lat, n.lon) for n in w.nodes]
            if 24.9 < points[0][0] < 24.98 and 121.32 < points[0][1] < 121.43:
                self.platforms.append(points)


def metres(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((b[0] - a[0]) * 111_320, (b[1] - a[1]) * 111_320 * k)


def middle(points):
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def main():
    ways = Ways()
    ways.apply_file(sys.argv[1], locations=True)
    crossover = ways.ways[CROSSOVER]
    sidings = [ways.ways[i] for i in SIDINGS]
    print("junction", middle([crossover[0], crossover[-1]]))
    print("yard start", middle([s[-1] for s in sidings]))
    print("yard end", middle([s[0] for s in sidings]))
    sides = sorted(round(max(metres(p[i], p[i + 1]) for i in range(len(p) - 1)), 1) for p in ways.platforms)
    print("platforms", len(sides), "longest sides", sides[0], "to", sides[-1], "m")

    # Danhai: the tracks' ends nearer the depot (the north), and the yard
    # tracks' east and west ends.
    ends = [max((w[0], w[-1])) for w in (ways.ways[i] for i in DANHAI_ENDS)]
    yard = [sorted((w[0], w[-1]), key=lambda p: p[1]) for w in (ways.ways[i] for i in DANHAI_YARD)]
    print("danhai junction", middle(ends))
    print("danhai yard start", middle([y[1] for y in yard]))
    print("danhai yard end", middle([y[0] for y in yard]))

    # Decision 535: the Wenhu Line's depots. The tracks' ends nearer the
    # leads, and each yard track's end nearer the leads and its far end.
    for name, end_ids, yard_ids, lead_ids in (
        ("muzha", MUZHA_ENDS, MUZHA_YARD, MUZHA_LEADS), ("neihu", NEIHU_ENDS, NEIHU_YARD, NEIHU_LEADS)
    ):
        tracks = [ways.ways[i] for i in end_ids]
        leads = [ways.ways[i] for i in yard_ids if i in ways.ways]
        # Each main track's end where a lead begins.
        starts = [p for i in lead_ids for p in (ways.ways[i][0], ways.ways[i][-1])]
        ends = [min((w[0], w[-1]), key=lambda p: min(metres(p, q) for q in starts)) for w in tracks]
        junction = middle(ends)
        near = [min((w[0], w[-1]), key=lambda p: metres(p, junction)) for w in leads]
        far = [max((w[0], w[-1]), key=lambda p: metres(p, junction)) for w in leads]
        print(f"{name} junction", junction)
        print(f"{name} yard start", middle(near))
        print(f"{name} yard end", middle(far))
        print(f"{name} yard tracks", len(leads), "longest", round(max(metres(n, f) for n, f in zip(near, far)), 1), "m")

    # Decision 535 (continued): the Ankeng depot.
    crossover = [p for i in ANKENG_CROSSOVER for p in (ways.ways[i][0], ways.ways[i][-1])]
    yard = [sorted((ways.ways[i][0], ways.ways[i][-1])) for i in ANKENG_YARD]
    print("ankeng junction (crossover)", middle(crossover))
    print("ankeng yard start (north ends)", middle([y[1] for y in yard]))
    print("ankeng depot north end", max(ways.ways[ANKENG_DEPOT]))
    print("ankeng tracks' end", middle([min((w[0], w[-1])) for w in (ways.ways[i] for i in ANKENG_ENDS)]))
    print("ankeng yard south ends", middle([y[0] for y in yard]))
    print("ankeng yard tracks", len(yard), "longest", round(max(metres(a, b) for a, b in yard), 1), "m")


if __name__ == "__main__":
    main()
