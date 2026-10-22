# Web/CityView fixed captures

`capture.cjs` opens the local Web/CityView page in the preinstalled Playwright Chromium. It holds the date, `__app.clockTime`, picture variant, viewport, traffic, birds and clouds fixed; it waits for the selected tiles, drives `__app.tick()` by hand, and saves one PNG per camera plus `measurements.json`. It does not install Playwright or download a browser.

## Run

From the repository root, first install the **existing** CityView lockfile and provide the compiled city data and textures (see [procedural city setup](../procedural-city/README.md)). Both `Web/CityView/public/tiles/` and `Web/CityView/public/textures/` are ignored build inputs. The tool fails if tiles or page resources are missing.

```sh
(cd Web/CityView && npm ci)
NODE_PATH=/path/to/preinstalled/node_modules node tools/cityview-benchmark/capture.cjs --out /tmp/cityview-captures
```

In the managed Linux environment, Playwright is at `/opt/codex/cua_node/lib/node_modules`, so `NODE_PATH=/opt/codex/cua_node/lib/node_modules` works. The script uses the system's preinstalled `/usr/bin/chromium` when present; set `CHROMIUM_PATH` for another installed Chromium. Use `--camera station-day` (or `station-night`, `district-day`) for one view, `--frames 30` to change the number of timed frames, `--warmup 8` to change the untimed frames, and `--port 5288` if that local port is occupied. The script starts and stops Vite. All cameras use Kaohsiung's compiled tiles and a 960 × 540 Chromium viewport at device scale 1.

The camera list and frozen settings are in `capture.cjs`. The two station cameras share the same position and differ only by clock hour. For a repeatability check, run `station-day` twice into different output directories and compare `views[0].drawCalls` and `views[0].frameMs` in the two JSON files.

A Linux example capture is in [`examples/linux-2026-10-20/`](examples/linux-2026-10-20/): its JSON and `district-day.png`. The other two PNGs are in `a91453/railway-reference-private: Railway/game-art-previews/tools/cityview-benchmark/examples/linux-2026-10-20/`. Keep a new capture's PNGs out of this repository except one overview (`docs/HANDOFF.md` §2).

## Output

`station-day.png`, `station-night.png` and `district-day.png` are canvas captures. `measurements.json` has one `views` entry per PNG:

```json
{
  "id": "station-day",
  "png": "station-day.png",
  "area": "kaohsiung",
  "camera": [0, 0, 420, 200, 32],
  "hour": 12,
  "drawCalls": 123,
  "triangles": 456789,
  "frameMs": { "median": 12.3, "p95": 15.6 }
}
```

The numbers above only illustrate the JSON shape. `drawCalls` and `triangles` come from `renderer.info.render` after each `tick()`. The script requires them to be nonzero and equal in every timed frame, so a loading or changing scene fails. `frameMs` is wall clock time inside Chromium for `tick()` followed by `gl.finish()`, after warmup. The median is the middle time and p95 is the interpolated 95th percentile. Lower frame times and lower render counts usually mean less work, but compare runs only with the same camera, data, viewport, browser, graphics driver and machine load. `gl.finish()` includes a GPU completion wait and is not an on device FPS measurement.

This measures the **web Three.js/WebGL CityView**, not the app's native Metal 3D. The historical RTX 5090 numbers in `Web/CityView/performance.md` used a different resolution and scripts; do not compare their milliseconds directly with this tool's output.
