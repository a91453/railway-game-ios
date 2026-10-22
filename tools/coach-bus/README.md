# Three-axle high-deck coach

One new warm-white/warm-red native coach, recomposed from four owner-supplied images. The already styled teal shuttle, blue low-floor bus and existing city bus are three comparisons, not new vehicle types. `Map3DCoachBus.model()` / `Map3DStreetModel.coachBus` / `life-coachBus`.

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/coach-bus/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html: filters/search, seven directions, rotate/zoom, backgrounds, PNG/native/GLB downloads. Existing station-kit binary/GLB/renderer and shuttle/civic closed geometry are reused; no new dependencies or external calls.

Native axes +x front/+y left/+z up, metres. Approximate length13.19m, body2.50m wide, mirrors3.16m, equipment3.76m high, wheel bottom0. Three actual axles, open concave arches, raised glazing, right-front door and contact steps, luggage hatches, two physical windscreen slopes, supported mirrors and HVAC, head/tail glow. Matte opaque paint uses shopAwnings[3]/[1]. The luggage doors have closed 7mm shells, body-matched unshaded faces,12mm fine seams and small flush grips; avoid addBox side shading turning them into grey boxes. No logos, brands or raw copied textures/models.

The existing5% bus pool keeps30% shuttle and35% low-floor, then20% coach and15% old city bus. (Current mix: 30% shuttle, 35% low-floor, 20% coach, 10% midi, 5% old city bus; see `Map3DStreetLife.addVehicles`.) The first two seed selections are unchanged. Traffic density, bus cap, road eligibility and17m conservative spacing remain. No GameCore purchases/operations/save changes.

Outputs: 4 native/4 GLB/28 seven-view transparent PNGs; front/rear/underside, overview/directions/style/fleet comparison sheets and viewer. There is only1 new type. Source SHA/native round-trip/full GLB reconstruction, decoded PNG alpha/pixels/hashes, browser interactions and seven XCTest suites are checked. Inspect the actual sheets too. Metal/device performance, wheel/door animation, collisions and engineering dimensions remain unverified.

Open every PR against main. If it depends on an unmerged PR, wait for that one to merge or bring the needed parts in (#942, #949 and #957 once merged into stale branches).

[Claude/Codex extension workflow](../../.claude/skills/coach-bus/SKILL.md).
