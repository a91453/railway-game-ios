# 高鐵兩款與 E200 接進營運：前後對照（決策 408）

畫出高鐵十二節的之前（#900，每節 20 m）、700T（#1201，每節照自己的長度）、700T 在 500–900 m 換成的遠景模型、N700S-G，和莒光號 E200＋三節客車的之前與之後，照 `Map3DTrains.frame` 的排法（`TrainCars.cars`，每節拉到它那段軌跡的弦長）；直線與 120 m 半徑的彎道各一份，另畫三款的頭車近看（`cabs`）。`export.swift` 只畫遊戲裡的模型，不讀作者的原檔。印出每列的節數、長度、三角形數與模型包的大小（決策 408「量到的」）。`docs/art/hsr-trains-408/` 是結果。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
swiftc -swift-version 6 -I "$bin" tools/hsr-trains-408/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o OUT/export
OUT/export OUT
NODE_GLOBAL="$(npm root -g)/" node tools/hsr-trains-408/render.mjs OUT
python3 tools/train-pack-lrt/sheet.py OUT hsr.png "之前=hsr-before-iso,hsr-before-front" "700T=hsr-700t-iso,hsr-700t-front" ...
```

`export.swift` 用 `@testable import`，所以要 debug 版（從 `tools/codex-trains-399/` 改來）。`render.mjs` 同 399 的，但把 station-kit 繪圖器一個模型 15,000 個三角形的上限在它的副本裡放寬到 200,000（700T 一列七萬多）。Chromium 用 `/opt/pw-browsers/chromium-1243`（或 `CHROMIUM_PATH`），playwright 從全域 node_modules 讀（或 `NODE_GLOBAL`）。WebGL 的圖不代表 iPhone 的 Metal。

## N700S-G 的減面（`decimate.py`）

N700S-G 近處的三節（頭 A、中間 C、集電弓車 D）是作者自己的模型減面、換成遊戲的色票（決策 408 第 3 條）。原檔只在私庫，**不要複製進這個 repo**：從私庫的 checkout 讀。

```sh
# 私庫 a91453/railway-reference-private 的 checkout（sparse checkout 這個目錄就夠）
MODELS=<checkout>/Railway/n700s-n700st-2026-10-24/n700s-g/models
python3 -m venv <scratchpad>/venv && <scratchpad>/venv/bin/pip install numpy   # BSD，不進 repo
<scratchpad>/venv/bin/python -I tools/hsr-trains-408/decimate.py "$MODELS" Sources/GamePresentation/Map3DN700SGMesh.swift
```

約 10 秒，結果逐位元固定（同樣的原檔跑兩次 SHA-256 相同）。每節的預算與誤差加不加權在檔頭的 `UNITS`；作者的顏色對到調色盤的哪一格在 `COLOURS`，順序要和 `Map3DN700SG.meshPalette` 一樣，原檔多一個沒對到的顏色就停下。作者的轉向架（輪、架、軸箱蓋）減面前先拿掉，只把它們的中心寫成 `bogieCentres`，遊戲在那裡畫 700T 的轉向架。產生的 Swift 檔開頭記著每節減前減後的三角形數與原檔 SHA-256 的前 16 碼。減面的做法、選這組預算的理由與沒有選的試驗在 `docs/decisions/408.md`。
