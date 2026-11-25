# 高鐵兩款車的遠景（決策 422）

> 決策 979（2026-11-25）：N700S-G 換成作者舊版的 N700S（`Map3DN700S`，一節兩三千面，不另做遠景）。`n700sg_far.swift` 與它產生的 `Map3DN700SGFarMesh.swift` 已刪，要看在 git 歷史；下面 N700S-G 的指令是當時的紀錄，現在跑不了。

- `export.swift`：把 `highSpeed`、`highSpeedFar` 每種車廂寫成 M3DM（`tools/mesh-lod-420/render.mjs` 的格式）與 `manifest.json`，印出每節與十二節一列的三角形、頂點資料 MB、建好每組的時間。
- `distance.py`：把算好的圖排成 `docs/art/hsr-far-2026-10-26/overview.png`。

700T 的遠景不用工具：`Map3DTrainShapeRefresh.model(_:far:)` 在遊戲裡從近景的配方產生。

## 指令（在 repository 根目錄，Linux 的 Swift 6.4）

```sh
swift build
bin="$(swift build --show-bin-path)"
# N700S-G 的遠景車身（約 6 秒）
swiftc -O -swift-version 6 -I "$bin" tools/hsr-far-422/n700sg_far.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o /tmp/n700sg_far
/tmp/n700sg_far Sources/GamePresentation/Map3DN700SGFarMesh.swift
swift build   # 重新編進遊戲

# 數字與模型檔（main 上跑一次得到舊遠景，分支上再跑一次）
swiftc -swift-version 6 -I "$bin" tools/hsr-far-422/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o /tmp/export422
/tmp/export422 OUT/new
```

對照圖：把 main 與分支的 `OUT/*/models/<set>-head.m3dmodel` 複製成 `CMP/models/<train>-head-<near|newfar|oldfar>.m3dmodel`（`train` 是 `700t` 或 `n700`），寫一份 `CMP/manifest.json`（`{"models":[{"id":"700t-head-near","native":"models/700t-head-near.m3dmodel","group":"700t-head"}, …]}`，同一節車的三個放同一個 group，同一個鏡頭），然後：

```sh
NODE_GLOBAL="$(npm root -g)/" node tools/mesh-lod-420/render.mjs CMP
python3 -I tools/hsr-far-422/distance.py CMP docs/art/hsr-far-2026-10-26/overview.png
```
