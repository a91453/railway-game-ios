# ResidentialKit

24 optional static native game assets (eight homes, eight boundary/access parts and eight yard/street parts) plus four assembled scenes. Each model has M3DM v1, GLB and seven transparent 384px views generated from the same native geometry. Existing `tools/station-kit` code supplies the loader round trip, GLB encoder and renderer.

Requires Swift 6.4, Node, Python, Playwright and Chromium already installed. No new App dependency.

```sh
tools/residential-kit/rebuild.sh /absolute/path/to/private/output/residential-kit-2026-10-21
python3 -m http.server 8080 --directory /absolute/path/to/private/output/residential-kit-2026-10-21
```

Open `http://localhost:8080/` to search, filter, rotate, zoom, switch directions/backgrounds and download PNG/native/GLB. The viewer makes no external requests.

Use `Map3DResidentialKit.model(for:)` or `Map3DModelPack(residentialKit:)` to build chosen parts only. Native axes are +x front, +y left, +z up, in metres. Ground models start at z=0. `balconyModule` mounts at x=0 against a real wall; roof appliances mount atop a roof slab. The 15,000 triangle native limit applies to complete scenes as well as individual parts. These are stylised game assets, not surveyed residences or collision geometry.

See [.claude/skills/residential-kit/SKILL.md](../../.claude/skills/residential-kit/SKILL.md) for continuation and review rules. Native vertices, complete GLB bytes, PNG decode/hash/bounds, browser operations and targeted XCTest are checked locally; device Metal and live map placement require separate checks.
