# Commercial Kit

36 optional native game assets (12 commercial buildings, 12 shops & dining, 12 signage/facilities/transit bus) and four illustrative assemblies. Swift recipes produce native M3DM v1, GLB and seven transparent 384px PNGs per model. All generated views use the actual native vertices.

Requires the project's Swift 6.4, Node, Python, Playwright and Chromium. No new dependencies.

```sh
tools/commercial-kit/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html; filter/search, rotate/zoom, select seven views, download PNG/native/GLB. The viewer makes no external requests. The shared exporter/renderer lives in tools/station-kit. Large outputs belong in the private reference repository.

Use `Map3DCommercialKit.model(for:)` or `Map3DModelPack(commercialKit:)`. Native axes are +x front, +y left, +z up in metres. Ground mount at z=0, wall backing at x=0. All assemblies stay below the loader's 15,000 triangle limit. These are optional static game assets, not measured buildings or commercial simulation.

Read [.claude/skills/commercial-kit/SKILL.md](../../.claude/skills/commercial-kit/SKILL.md) for extension and review rules. Verification checks native vertex readback, complete GLB reconstruction, PNG dimensions/hash/visible bounds, browser interaction and the intended XCTest suite.
