#!/usr/bin/env python3
"""Where the Taiwan Railway's real track is on bridges and viaducts or in
tunnels (ARCHITECTURE decision 279), for the demos and the network tool to
lay their track at real heights.

    python3 tools/real-railways/extract_structures.py \\
        <railway-reference-private>/Railway/site_archive_clean/rail-3d/physical/network.json \\
        <railway-reference-private>/Railway/site_archive_clean/rail-3d/physical/level-profiles.json \\
        RailwayGameApp/Resources/RealRailways/tra_structures.json

The inputs are the owner's `Railway/` site's: `network.json`, its
OpenStreetMap railway ways (Overpass, ODbL 1.0), and `level-profiles.json`,
each way's structure as the site settled it (its `classifyRailStructure`,
`rail-3d/physical/structure-kind.js`): OpenStreetMap's own `bridge` and
`tunnel` tags, filled in where they are missing from the National Land
Surveying and Mapping Center's railway geometry (data.gov.tw 73220, Open
Government Data License 1.0), and the two weighed against the terrain where
they disagree. `layer` alone never makes a bridge or a tunnel.

What it keeps: every TRA running line (`system` `tra_sched`, no `service`
tag) the site calls a bridge or a tunnel, as the way's points, six
decimals (about 0.1 m). Heights are left out: the site's are estimates
(its `basis`), and the game lays its own over its own ground.
"""

import hashlib
import json
import sys


def main(network_path, profiles_path, out_path):
    with open(network_path, "rb") as f:
        network_bytes = f.read()
    with open(profiles_path, encoding="utf-8") as f:
        profiles = json.load(f)
    # The profiles were worked out from this very network.
    expected = profiles["inputSha256"]["network.json"]
    actual = hashlib.sha256(network_bytes).hexdigest()
    if actual != expected:
        sys.exit(f"network.json is {actual}, the profiles were made from {expected}")
    network = json.loads(network_bytes)
    entries = profiles["entries"]

    structures = []
    for way in network["ways"]:
        if way["system"] != "tra_sched" or "service" in way["tags"]:
            continue
        kind = entries.get(way["id"], {}).get("kind")
        if kind not in ("bridge", "tunnel"):
            continue
        points = [[round(lon, 6), round(lat, 6)] for lon, lat in way["coordinates"]]
        structures.append({"way": way["id"], "kind": kind, "points": points})
    structures.sort(key=lambda s: (len(s["way"]), s["way"]))

    out = {
        "_readme": "Where the TRA's running lines are on bridges and viaducts (bridge) or in tunnels (tunnel), "
        "one way of the site's network each (an OpenStreetMap way, or a link the site added). Made by tools/real-railways/extract_structures.py (decision 279); do not edit.",
        "source": {
            "openStreetMap": {
                "attribution": "© OpenStreetMap contributors",
                "license": "ODbL-1.0",
                "at": network["source"]["at"],
            },
            "official": {
                "attribution": "內政部國土測繪中心「臺灣鐵路」",
                "url": "https://data.gov.tw/dataset/73220",
                "license": "Open Government Data License 1.0",
            },
            "networkSha256": actual,
            "profilesSha256": hashlib.sha256(open(profiles_path, "rb").read()).hexdigest(),
        },
        "structures": structures,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    counts = {k: sum(1 for s in structures if s["kind"] == k) for k in ("bridge", "tunnel")}
    print(f"{len(structures)} ways: {counts}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
