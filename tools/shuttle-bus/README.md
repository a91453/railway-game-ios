# High-roof shuttle bus

One new native 6.78 m shuttle minibus, teal/off-white, recomposed from four owner-supplied views; one existing fitted 12 m city bus is exported for comparison. New type is `Map3DStreetModel.shuttleBus`, native model `life-shuttleBus`.

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/shuttle-bus/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html. Filter/search, seven directions, rotate/zoom, change background and download PNG/native/GLB. Existing Swift6.4/Node/Python/Playwright/Chromium suffice; no new dependencies. Native/GLB/renderer reused from station-kit; no raw reference model copied.

Native axes +x front/+y left/+z up, metres. Body width2.08m, mirrors below2.8m, roof2.88m, wheel bottom0. Right passenger door lies on negative y. Concave body contours use ear clipping to preserve real wheel openings; windscreen follows body rake. Head/tail lamps glow. Matte opaque livery uses existing shopAwnings palette entries.

Map3DStreetLife chooses the shuttle for 30% of its original bus pool. Total bus share5%, traffic density, bus cap and conservative spacing remain. Both types are counted by isBus; the original Meshy bus still loads normally. No GameCore vehicle catalogue/save changes.

Outputs: 2 native/2 GLB/14 transparent PNGs, front/rear/underside hero images, overview/seven-view/style/old-bus comparison sheets and viewer. Rebuild checks native position/colour/glow readback with normal tolerance1e-5, full GLB reconstruction/hashes, PNGs, browser interactions and five intended XCTest suites. Inspect the images; byte checks do not judge shape. Real-device Metal/performance and wheel/door animation remain separate.

[Extension workflow](../../.claude/skills/shuttle-bus/SKILL.md).
