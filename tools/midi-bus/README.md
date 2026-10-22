# Rounded cab-over midibus

One new warm-white/teal native midibus, recomposed from four owner-supplied views. Four existing vehicles are comparisons: shuttle, low-floor, coach (refined flush luggage hatches), and fitted city bus. References are not new types. `Map3DMidiBus.model()` / `Map3DStreetModel.midiBus` / `life-midiBus`.

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/midi-bus/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html for filters/search, seven directions, orbit/zoom, backgrounds, PNG/native/GLB downloads. Reuses station-kit binary/GLB/renderer and shuttle/civic closed geometry, no new dependencies. [Complete copy-paste handoff prompt](../../docs/art/VEHICLE_ASSET_HANDOFF_PROMPT.md) and [skill](../../.claude/skills/midi-bus/SKILL.md).

Metres, native +x front/+y left/+z up. About9.15m long,2.38m body width,2.91m including mirrors,3.16m high; wheel bottom0. Two real open arches, backed panoramic glazing curved in height and plan, a rounded-shoulder longitudinal roof loft, right-front double passenger door, left-rear emergency/equipment hatch. Clean body-coloured covers and small seams; no thick grey luggage boxes. Actual source engineering dimensions/brand are not asserted. Matte opaque shopAwnings[3]/[0], native glow lamps, no logos or copied source mesh/textures.

Original5% bus pool becomes30% shuttle/35% low-floor/20% coach/10% midibus/5% old city. First three seed selections, density, cap, eligible roads and17m conservative spacing remain unchanged. No GameCore rules or save changes.

5 native/5 GLB/35 seven-view RGBA PNGs; front/rear/underside, overview, direction/style/comparison/same-scale fleet sheets and interactive viewer. Verification covers native full vertex round-trip, full GLB reconstruction, hashes, PNG full decode/alpha/pixel counts, browser interactions, eight touched XCTest suites and Node packaging tests. Manually inspect actual sheets too. Device Metal/performance, wheel/door animation and vehicle collision physics remain unverified.

Open every PR against main. If it depends on an unmerged PR, wait for that one to merge or bring the needed parts in (#942, #949 and #957 once merged into stale branches). Verify current remote status before starting another task. Large outputs stay private in `Railway/game-art-previews/docs/art/midi-bus-2026-10-21/`.

Streamline refinement: slimmer outward-facing window ribbons, swept headlamps and painted apron, an integrated destination brow clipped from actual planar roof triangles, and no square rooftop hatches. Optional `previews/streamline-before-hero.png` and `streamline-before-right.png` create a same-angle before/after sheet using previous native renders. These are previews, not new models.
