# 網格簡化與遠景車的對照（決策 420）

`export.swift` 把幾款車的頭車（和路線公車）寫成 M3DM：完整、遊戲的簡化器（`Map3DMeshSimplifier`）50 %／25 %／10 %、程式版遠景車、盒子，並印出三角形數與時間；`render.mjs`（`tools/train-modeling-410/render.mjs` 改來）同一組相機畫斜前與正側；`overview.py` 拼成 `docs/art/mesh-lod-2026-10-26/` 的總圖。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
swiftc -swift-version 6 -I "$bin" tools/mesh-lod-420/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o OUT/export
OUT/export OUT
NODE_GLOBAL="$(npm root -g)/" node tools/mesh-lod-420/render.mjs OUT
python3 tools/mesh-lod-420/overview.py OUT overview-front.png front
python3 tools/mesh-lod-420/overview.py OUT overview-side.png side
```

`export.swift` 用 `@testable import`，所以要 debug 版。全部模型的簡化時間與記憶體要 release 版：

```sh
swift build -c release --build-tests -Xswiftc -enable-testing
MAP3D_LOD_REPORT=1 swift test -c release --skip-build --filter Map3DModelLODReportTests
```
