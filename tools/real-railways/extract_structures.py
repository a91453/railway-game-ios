#!/usr/bin/env python3
"""Where Taiwan's real railways are on bridges and viaducts or in tunnels
(ARCHITECTURE decision 279): the TRA's, the High Speed Rail's and the Alishan
Forest Railway's running lines, and since 2026-10-21 the metros' and light
rails', for the demos and the network tool to lay their track at real
heights.

    R=<railway-reference-private>/Railway/taiwan-rail-reference-clean/source/rail-3d/physical
    python3 tools/real-railways/extract_structures.py \\
        "$R/network.json" "$R/metro-network.json" "$R/level-profiles.json" \\
        RailwayGameApp/Resources/RealRailways/rail_structures.json

The inputs are the owner's Taiwan rail website's, its newer snapshot
`Railway/taiwan-rail-reference-clean/` (2026-10-18; the first run read the
older `Railway/site_archive_clean/`): `network.json` and
`metro-network.json`, its OpenStreetMap railway and metro ways (Overpass,
ODbL 1.0), and `level-profiles.json`,
each way's structure as the site settled it (its `classifyRailStructure`,
`rail-3d/physical/structure-kind.js`): OpenStreetMap's own `bridge` and
`tunnel` tags, filled in where they are missing from the National Land
Surveying and Mapping Center's railway, high-speed railway and metro
geometry (data.gov.tw 73220, 73221 and 73222, Open Government Data License
1.0), and the two
weighed against the terrain where they disagree. `layer` alone never makes a
bridge or a tunnel.

What it keeps: every running line of `SYSTEMS` and `METRO_SYSTEMS` (no
`service` tag) the site
calls a bridge or a tunnel, with its system, as the way's points, six
decimals (about 0.1 m). Heights are left out: the site's are estimates
(its `basis`), and the game lays its own over its own ground.
"""

import hashlib
import json
import sys

# The systems the game builds on real alignments, as the site and the game
# both name them: the TRA, the High Speed Rail and the Alishan Forest Railway
# (`network.json`), then Taipei's metro (with the Circular Line), Taoyuan's
# airport line, the Danhai and Ankeng light rails, the Sanying Line,
# Kaohsiung's metro and light rail and Taichung's metro
# (`metro-network.json`).
SYSTEMS = ("tra_sched", "thsr_sched", "afr_sched")
METRO_SYSTEMS = ("mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt")


def read_network(path, name, profiles):
    """A network file's bytes' sha256 and its ways, once its sha256 is the
    one the profiles were worked out from."""
    with open(path, "rb") as f:
        data = f.read()
    expected = profiles["inputSha256"][name]
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        sys.exit(f"{name} is {actual}, the profiles were made from {expected}")
    return actual, json.loads(data)


def main(network_path, metro_path, profiles_path, out_path):
    with open(profiles_path, encoding="utf-8") as f:
        profiles = json.load(f)
    network_sha, network = read_network(network_path, "network.json", profiles)
    metro_sha, metro = read_network(metro_path, "metro-network.json", profiles)
    entries = profiles["entries"]
    systems = SYSTEMS + METRO_SYSTEMS

    structures = []
    for way in network["ways"] + metro["ways"]:
        if way["system"] not in systems or "service" in way["tags"]:
            continue
        kind = entries.get(way["id"], {}).get("kind")
        if kind not in ("bridge", "tunnel"):
            continue
        points = [[round(lon, 6), round(lat, 6)] for lon, lat in way["coordinates"]]
        structures.append({"way": way["id"], "system": way["system"], "kind": kind, "points": points})
    structures.sort(key=lambda s: (len(s["way"]), s["way"]))

    out = {
        "_readme": "Where the running lines of the TRA, the High Speed Rail, the Alishan Forest Railway and the metros and light rails are on bridges and viaducts (bridge) or in tunnels (tunnel), "
        "one way of the site's network each (an OpenStreetMap way, or a link the site added). Made by tools/real-railways/extract_structures.py (decision 279); do not edit.",
        "source": {
            "openStreetMap": {
                "attribution": "© OpenStreetMap contributors",
                "license": "ODbL-1.0",
                "at": network["source"]["at"],
                "metroAt": metro["source"]["at"],
            },
            "official": {
                "attribution": "內政部國土測繪中心「臺灣鐵路」「高速鐵路」「捷運」",
                "url": "https://data.gov.tw/dataset/73220 https://data.gov.tw/dataset/73221 https://data.gov.tw/dataset/73222",
                "license": "Open Government Data License 1.0",
            },
            "networkSha256": network_sha,
            "metroNetworkSha256": metro_sha,
            "profilesSha256": hashlib.sha256(open(profiles_path, "rb").read()).hexdigest(),
        },
        "structures": structures,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    counts = {(system, kind): sum(1 for s in structures if s["system"] == system and s["kind"] == kind)
              for system in systems for kind in ("bridge", "tunnel")}
    print(f"{len(structures)} ways: {counts}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
