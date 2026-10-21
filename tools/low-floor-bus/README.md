# Two-door low-floor city bus

One new native 12.08 m full-size bus, warm white/muted blue, recomposed from the owner's four supplied views. The existing fitted city bus is exported as a comparison, not counted as new. Native name `life-lowFloorBus`, street type `Map3DStreetModel.lowFloorBus`.

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/low-floor-bus/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html for search, category filters, seven views, rotation/zoom, backgrounds and PNG/native/GLB downloads. Reuses the existing station-kit exporter, closed geometry and renderer; no new dependencies or external requests.

Native axes +x front/+y left/+z up, metres. Body width2.46m, mirror width3.05m, equipment height3.40m, tyre bottom0. The right (negative y) has front/middle double doors. The raked windscreen and side glazing have solid backing; concave wheel openings are ear-clipped; roof HVAC has contact feet and closed housing. No logos or brand text. Fixed opaque paint is taken from shopAwnings[3] and [2].

The original5% bus pool now chooses30% shuttle,35% new low-floor and35% existing city bus. Shuttle selection remains unchanged. isBus covers all three; traffic density/cap, road eligibility and17m conservative spacing remain. No GameCore vehicle purchase, fares, save or simulation changes.

Outputs: 2 native/2 GLB/14 transparent seven-view PNGs, front/rear/underside images, overview/directions/style/comparison sheets and interactive viewer. Verification covers native round-trip, full GLB reconstruction and SHA, decoded PNG alpha/pixels, browser operations and six intended XCTest suites. Inspect the actual sheets too. Device Metal appearance/performance, wheel/door animation and collision physics remain unverified.

This task is stacked on shuttle-bus PR#941 while it is open. Keep that base until it merges, then retarget this PR to main; do not duplicate or squash the earlier task into this diff.

[Extension workflow](../../.claude/skills/low-floor-bus/SKILL.md).
