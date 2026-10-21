# Park Kit

36 optional native game assets: 12 playground, 12 sport, 12 garden; four assemblies. Native M3DM v1, embedded-buffer GLB and seven transparent 384px PNGs per model, all from the same actual native vertices.

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/park-kit/rebuild.sh /absolute/path/outside/public/checkout
python3 -m http.server 8080 --directory /absolute/path/outside/public/checkout
```

Open localhost:8080/index.html. Search/filter, seven views, pointer orbit, zoom, background selection and PNG/native/GLB downloads work without external requests. Uses existing Swift6.4, Node, Python, Playwright and Chromium; no new dependencies. Shared exporter/renderer in tools/station-kit; closed tube/legs from CivicKit.

Native axes +x front/+y left/+z up, metres. All parts ground at z=0. Bridge end deck connectors x=±2.5,z=.12; ground abutments remain at z=0. Basketball court hoopA/B connectors account for its .08 high surface. Every part and assembly stays under native loader 15,000 triangles. No physics, animation or safety certification.

[Extension workflow](../../.claude/skills/park-kit/SKILL.md). Large outputs and ZIP belong in the private reference repository. Verify native vertex readback, complete GLB reconstruction, PNGs, browser interaction and actual intended XCTest suite results. Inspect category, assembly, underside, seven-view and four-background sheets. WebGL does not establish iOS Metal performance or live map adoption.
