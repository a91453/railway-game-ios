# Civic Kit

48 optional native game assets (12 public buildings, 24 furniture, 12 temple/market parts) and four illustrative assemblies. Swift recipes produce native M3DM v1, GLB and seven transparent 384px PNGs per model. All generated views use the actual native vertices.

Requires the project's Swift 6.4, Node, Python, Playwright and Chromium. No new dependencies.

```sh
tools/civic-kit/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html; filter/search, rotate/zoom, select seven views, download PNG/native/GLB. The viewer makes no external requests. The shared exporter/renderer lives in tools/station-kit. Large outputs belong in the private reference repository.

Use `Map3DCivicKit.model(for:)` or `Map3DModelPack(civicKit:)`. Native axes are +x front, +y left, +z up in metres. Ground mount at z=0, wall backing at x=0, ceiling mount at z=0 extending downward. `writingDesk.desktop` is z=.80; wall parts require a wall; projector requires a ceiling/beam. All assemblies stay below the loader's 15,000 triangle limit. These are optional static game assets, not measured buildings or emergency-service simulation.

Read [.claude/skills/civic-kit/SKILL.md](../../.claude/skills/civic-kit/SKILL.md) for extension and review rules. Verification checks native vertex readback, complete GLB reconstruction, PNG dimensions/hash/visible bounds, browser interaction and the three intended XCTest suites. Inspect category/assembly/underside/direction/style sheets too. iOS Metal, performance and live map adoption remain separate verification.
