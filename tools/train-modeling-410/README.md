# 程序列車重建的前後對照（決策 410）

畫出每款程式畫的列車（`Map3DTrainShell`）在 main 與分支上的樣子，同一個相機。`export.swift` 把每款排成短列（頭車、一節中間車、尾車；單節的柴油客車一節）車頭朝 +x，以及場景套件的列車主題；先在 main 的 checkout 跑一次（`before`），再在分支跑一次（`after`），寫進同一個目錄，兩次的同一款落在同一組，`render.mjs` 用同一個相機畫（正側、斜前、車頭近看）。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
swiftc -swift-version 6 -I "$bin" tools/train-modeling-410/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o OUT/export
OUT/export OUT after          # 在 main 的 checkout（git worktree）用同樣的指令跑一次，最後一個參數是 before
NODE_GLOBAL="$(npm root -g)/" node tools/train-modeling-410/render.mjs OUT
python3 tools/train-modeling-410/overview.py OUT overview.png
python3 tools/train-pack-lrt/sheet.py OUT set-emu800.png "之前=set-emu800-before-iso,set-emu800-before-front" "之後=set-emu800-after-iso,set-emu800-after-front"
```

在 main 跑時，`export.swift` 要從分支複製過去（main 上沒有這個目錄）；main 沒有 `Map3DTrainShell.Detail`，把 `detail:` 那幾行拿掉。`export.swift` 用 `@testable import`，所以要 debug 版。`render.mjs` 是 `tools/hsr-trains-408/` 的副本。Chromium 用 `/opt/pw-browsers/chromium-1243`（或 `CHROMIUM_PATH`），playwright 從全域 node_modules 讀（或 `NODE_GLOBAL`）。WebGL 的圖不代表 iPhone 的 Metal。印出的每款三角形數（頭／中間／尾）是決策 410「量到的」。
