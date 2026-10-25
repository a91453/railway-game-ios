# 高鐵兩款與 E200 接進營運：前後對照（決策 408）

畫出高鐵十二節的之前（#900，每節 20 m）、700T（#1201，每節照自己的長度）、700T 在 500–900 m 換成的遠景模型、N700S-G，和莒光號 E200＋三節客車的之前與之後，照 `Map3DTrains.frame` 的排法（`TrainCars.cars`，每節拉到它那段軌跡的弦長）；直線與 120 m 半徑的彎道各一份，另畫三款的頭車近看（`cabs`）。作者的原始模型不讀，這個工具只畫遊戲裡的模型。印出每列的節數、長度、三角形數與模型包的大小（決策 408「量到的」）。`docs/art/hsr-trains-408/` 是結果。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
swiftc -swift-version 6 -I "$bin" tools/hsr-trains-408/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o OUT/export
OUT/export OUT
NODE_GLOBAL="$(npm root -g)/" node tools/hsr-trains-408/render.mjs OUT
python3 tools/train-pack-lrt/sheet.py OUT hsr.png "之前=hsr-before-iso,hsr-before-front" "700T=hsr-700t-iso,hsr-700t-front" ...
```

`export.swift` 用 `@testable import`，所以要 debug 版（從 `tools/codex-trains-399/` 改來）。`render.mjs` 同 399 的，但把 station-kit 繪圖器一個模型 15,000 個三角形的上限在它的副本裡放寬到 200,000（700T 一列七萬多）。Chromium 用 `/opt/pw-browsers/chromium-1243`（或 `CHROMIUM_PATH`），playwright 從全域 node_modules 讀（或 `NODE_GLOBAL`）。WebGL 的圖不代表 iPhone 的 Metal。
