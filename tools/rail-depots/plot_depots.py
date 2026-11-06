#!/usr/bin/env python3
"""Decision 602: the Wenhu Line's two depots as the game lays them, drawn
over OpenStreetMap's yards (osmtoday.com's asia/taiwan.pbf, ODbL), one
row per game dump.

    WENHU_DEPOT_DUMP=after.json swift test --skip-build \\
        --filter WenhuLineTests/testDumpTheDepotTrack
    python3 -I plot_depots.py taiwan.pbf out.png after.json [more.json ...]

Each dump is a row: Muzha on the left, Neihu on the right, metres east and
north of the site's throat (`RealLineDepotSite.Fan.throat`). Orange: OSM's
railway ways; thin lines: the game's track, coloured by rail height (0 m
purple to 40 m yellow); star: the game's depot station; dashed: the depot's
land (landuse=railway); blue: water.
"""
import json
import math
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import os

import osmium

SITES = [
    ("木柵機廠", (25.001270, 121.585081), 670, 71266521),
    ("內湖機廠", (25.058581, 121.621212), 600, 499801370),
]
REACH = 900  # metres around each throat read from OSM


def metres(origin, lat, lon):
    k = 111_320.0
    return ((lon - origin[1]) * k * math.cos(math.radians(origin[0])), (lat - origin[0]) * k)


class Reader(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = {i: {"rail": [], "road": [], "river": [], "water": [], "building": [], "land": []}
                     for i in range(len(SITES))}

    def way(self, w):
        tags = w.tags
        kind = None
        if "railway" in tags and tags["railway"] in ("rail", "subway", "light_rail", "monorail", "narrow_gauge"):
            kind = "rail"
        elif tags.get("highway") in ("motorway", "trunk", "primary", "secondary", "motorway_link", "trunk_link"):
            kind = "road"
        elif tags.get("waterway") in ("river", "stream", "canal"):
            kind = "river"
        elif tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
            kind = "water"
        elif "building" in tags:
            kind = "building"
        if kind is None and tags.get("landuse") != "railway":
            return
        try:
            points = [(n.location.lat, n.location.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        for i, (_, origin, _, land) in enumerate(SITES):
            local = [metres(origin, *p) for p in points]
            if not any(abs(x) < REACH and abs(y) < REACH for x, y in local):
                continue
            if w.id == land:
                self.ways[i]["land"].append(local)
            elif kind:
                self.ways[i][kind].append(local)


def main():
    pbf, out, dumps = sys.argv[1], sys.argv[2], sys.argv[3:]
    for f in font_manager.findSystemFonts():
        if "wqy" in f.lower() or "noto" in f.lower() and "cjk" in f.lower():
            font_manager.fontManager.addfont(f)
            plt.rcParams["font.family"] = font_manager.FontProperties(fname=f).get_name()
            break
    plt.rcParams["axes.unicode_minus"] = False
    reader = Reader()
    reader.apply_file(pbf, locations=True)
    games = [json.load(open(d)) for d in dumps]
    fig, axes = plt.subplots(len(games), 2, figsize=(12.8, 6.4 * len(games)), squeeze=False)
    cmap = plt.get_cmap("viridis")
    for row, (game, name) in enumerate(zip(games, dumps)):
        for i, (title, origin, extent, _) in enumerate(SITES):
            ax = axes[row][i]
            w = reader.ways[i]
            for poly in w["building"]:
                ax.fill(*zip(*poly), color="#e6ddd2", lw=0)
            for poly in w["water"]:
                ax.fill(*zip(*poly), color="#bcd6ee", lw=0)
            for line in w["river"]:
                ax.plot(*zip(*line), color="#7fb0dc", lw=2.5)
            for line in w["road"]:
                ax.plot(*zip(*line), color="#d9c9a8", lw=1.2)
            for poly in w["land"]:
                ax.plot(*zip(*poly), color="#777", lw=0.9, ls="--")
            for line in w["rail"]:
                ax.plot(*zip(*line), color="#d2691e", lw=1.4)
            site = game["sites"][i]
            for edge in site["edges"]:
                xy = [metres(origin, p[0], p[1]) for p in edge]
                height = sum(p[2] for p in edge) / len(edge)
                ax.plot(*zip(*xy), color=cmap(min(max(height / 40, 0), 1)), lw=0.7)
            if site["station"]:
                ax.plot(*metres(origin, site["station"][0], site["station"][1]), marker="*", color="green", ms=12)
            window = os.environ.get("PLOT_WINDOW")  # "x0,x1,y0,y1;x0,x1,y0,y1": a closer look
            if window:
                x0, x1, y0, y1 = map(float, window.split(";")[i].split(","))
            else:
                x0, x1, y0, y1 = -extent, extent, -extent, extent
            ax.set_xlim(x0, x1)
            ax.set_ylim(y0, y1)
            ax.set_aspect("equal")
            ax.grid(color="#eee")
            ax.set_title(f"{title}　橘＝OSM 真實（ODbL）細線＝遊戲（顏色＝軌面高度 0 紫→40 m 黃）{name.split('/')[-1]}", fontsize=9)
    fig.tight_layout()
    fig.savefig(out, dpi=100)


if __name__ == "__main__":
    main()
