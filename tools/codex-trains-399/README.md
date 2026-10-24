# Codex 的四款列車接進營運：前後對照（決策 399）

畫出仲夏寶島號、蒸汽列車、線性馬達捷運、輕型捷運四節，之前與之後各一列（四節），照 `Map3DTrains.frame` 的排法：之前每節 20 m（`TrainCars.cars(body:heading:count:gap:)`），之後每節照模型的長度（`Map3DModelPack.layout`、`TrainCars.cars(body:heading:lengths:gaps:)`）；另畫一份 120 m 半徑的彎道。`docs/art/codex-trains-399/` 是結果。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
swiftc -swift-version 6 -I "$bin" tools/codex-trains-399/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o OUT/export
OUT/export OUT                      # 印出每列的節數、長度、三角形數與模型包的大小
node tools/codex-trains-399/render.mjs OUT
python3 tools/train-pack-lrt/sheet.py OUT summer.png "仲夏寶島號 前=summer-before-iso,summer-before-front" ...
```

`export.swift` 用 `@testable import`，所以要 debug 版。Chromium 用 `/opt/pw-browsers/chromium-1243`（或 `CHROMIUM_PATH`），playwright 從全域 node_modules 讀（或 `NODE_GLOBAL`）。WebGL 的圖不代表 iPhone 的 Metal。
