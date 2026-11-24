# MODELS-145-tw-landmarks：145 模型接回 A 台灣地標

## 進度

- 做到哪：八座登錄地標（慈恩塔、拉魯島、臺中國家歌劇院、路思義教堂、衛武營、赤崁樓、文武廟前殿與後殿）已接進台灣 3D 地圖（決策 928）。**關渡大橋、夜市三件還沒接**（之後都接了：關渡大橋決策 944、夜市三件決策 935）。
- 已驗證：Linux `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`Map3DLandmarkRegistryTests`（4）、`Map3DPaletteGuardTests`（2）、`SunMoon|Landmark|Map3DTaiwan` 過濾到的測試全過；`doc_numbers.py --check` 過。台灣地圖登錄地標近景 44,216／60,000 個三角形（含決策 926、927 的四座；關渡大橋再加 3,168）。
- 下一步的第一個指令：`sed -n 1,80p Sources/GamePresentation/Map3DRoadBridge.swift`（先看關渡大橋那一段公路橋怎麼畫，再決定橋面對齊哪一種）。

派工：「鐵道遊戲主規劃 3」協調者（session_01JMHz9ZYaf6dBe9otGWsXhV）。實作 session：session_01JMHz9a3iMFJ1BJqHyhhrHb。分支 `claude/models-145-tw-landmarks`。決策 928。存檔版本、golden schema、GameCore 不動。

## 還留下什麼

1. （已做，決策 944，`claude/guandu-bridge`：公路橋面照決策 873 抬到拱橋橋面上）**關渡大橋**（素材庫 `railway-assets-private-2` #299，`game-art-previews/docs/art/tw-landmark-guandu-bridge-2026-11/revision-2`，經驗檔 `docs/studio/lessons/tw-guandu-bridge.md`）。已查好的：
   - GLB 外框 E ±269.5、N ±10.3、Z −1…36.1（近景 3,168、遠景 988 個三角形）；材質 `archRed,hanger,deck,pier` = `mtrRed`、`tankSteel`、`portal`、`concrete`。橋面頂 Z = 16.0，水面 Z = 0，墩座入水 1 m → `--raise 1` 加 `sink: 1`。
   - OSM way 250500239：直線 534 m，方位 57.8°，中心 25.1255488, 121.4572397 → `--turn 32.2`。x 用 Int16 公分（±327 m），轉完半長 270 m 放得下。
   - **沒定的**：遊戲那裡的公路橋照決策 391 貼在河面，模型橋面在水面上 16 m。要嘛照決策 873 淡江大橋的做法（`Map3DRoadBridge.swift` 的 `Bound.flat`、`Map3DSuspensionBridge.all`、`hangsFromCables`）把這 539 m 的路面抬到 16 m、模型橋面比路面低 15 cm；要嘛那一段公路橋不畫、讓給模型。決策要寫用哪一種（工作室 README §9）。登錄地標只避開軌道，不管道路。
2. （已做，決策 935，`96a5c49`，進了 145：寫成 Swift 網格 `Map3DMeshyMarketTemple`，不走下面的 `.m3dmodel`／`Map3DSceneryProp`／`models.json`，遠景版不用；理由在決策 935 §2.1。下面是當時的原計畫，不必再做；NIGHT-MARKET-3 查過，2026-11-24）**夜市三件**（素材庫 #275，`meshy-night-market-2026-11/revision-1`，`nm-bulb-string`、`nm-canopy`、`nm-stall-cart`，各有 `-far`；經驗檔 `docs/studio/lessons/meshy-night-market.md`）。不是登錄地標，是街景小物：照該資料夾 README §9：`tools/meshy/models.json` 加三筆（正面 `+y`）、`tools/meshy/generated.json` 照 `SOURCE.md` 抄 task 與點數、`tools/glb-to-m3dmodel` 轉成 `RailwayGameApp/Resources/Models/meshy-nm-*.m3dmodel`、`Map3DSceneryProp` 加三個 case、`Map3DModelPack`、`Map3DModelTests` 的總數、擺在 `nightMarketAlley`、`DataSourceCredits` 的 Meshy 一項加「夜市的燈泡串、帆布棚與小吃推車」（中英）；Xcode 專案若列資源要重新產生。PR 說明要有「經驗：railway-assets-private-2 docs/studio/lessons/meshy-night-market.md」。
3. （已做）「這版新增」：145 那一筆與 `.github/testflight-whats-new.md` 已各加八座地標的一行。
4. 決策 928 §3、§5 的 UNVERIFIED（路思義教堂入口朝向、文武廟後殿沒有照片、各座在地形上的落地高度與中殿台階的銜接、實機沒看過）。
