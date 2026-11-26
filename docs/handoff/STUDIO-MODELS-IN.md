# STUDIO-MODELS-IN：審過的工作室模型接進遊戲

## 進度

- 做到哪：上架前的三批（熊本城與水前寺、佛光山與野柳、香港三座廟）已合（#2768，決策 1018）；地標預算改成分區算、懸吊式單軌換 revision-3 是決策 1018 續。
- 已驗證：見 PR 的「驗證」一節。
- 下一步：0.6.1 的項目照下面的順序派單。

雲端工作串，分支 `claude/project-thread-qzu8e8`。存檔版本、golden schema、GameCore 都不動。對照表在專案共用資料夾 `studio-models-in/INVENTORY.md`，摘要在決策 1018 §1。原本登記的 1019、1020 已釋出。

## 怎麼接一件地標（照決策 895 的登錄制）

1. 用 `tools/landmarks/glb_to_swift.py` 把工作室的近景、遠景 GLB 轉成 `Map3D<Name>Mesh.swift`：`--materials` 照 GLB 材質順序、`--centre` 讓外框中心在原點、模型方位不對就 `--turn`（逆時針為正）、底要埋進地裡就 `--raise` 並在登錄寫同樣的 `sink:`。
2. 寫 `Map3D<Name>.swift`：調色盤只用 `Map3DPalette` 的色（`Map3DPaletteGuardTests`；工作室挑的是別的模型的色，就照決策 1018 §2.3 加進 `Map3DPalette` 並刪掉 `tools/palette-guard/baseline.txt` 對應那行），id 要寫成 `Map3DLandmarkRegistration(id: "…"` 字面（測試從原始碼找），登錄的經緯度用 OSM 的輪廓或節點，`size` 照轉檔印出的尺寸。
3. `Map3DLandmarkRegistryList.swift` 加一行。
4. `LANDMARK_LOCKS_WRITE=1 swift test --skip-build --filter Map3DLandmarkRegistryTests` 寫鎖檔 `tools/landmarks/locks/<id>.json`，再不帶變數跑一次。
5. PR 說明寫經驗檔 `railway-assets-private-2` `docs/studio/lessons/<model>.md`（`lessons-link.yml`）。
6. 預算（決策 1018 續，`Map3DLandmarkRegistryTests.testTheBudgets`）：任一塊 32 km 見方裡的近景合計 ≤ 60,000 三角形（台灣最滿的一塊 23,602）；整張地圖所有地標近景加遠景 ≤ 20 MB（台灣 9.9 MB）。

同一個模型擺好幾處（佛光山八塔、野柳蕈狀岩）照 `Map3DFukuokaTanks` 的 `model(_:as:)`（或 `Map3DFoGuangShanPagodas.model(as:)`）：同一份編碼，給每一處自己的 id。

## 0.6.1 的順序（要改規則、影響效能或要先補模型）

| 順序 | 素材庫資料夾 | 要先做的 |
| --: | --- | --- |
| 1 | `suizenji-garden-2026-11` 能樂殿、兩座石橋 | 工作室補遠景（能樂殿 ≤ 244、石橋 ≤ 130 三角形）；石橋西 3°、東 170°，各轉一次。補完照上面接，不動規則 |
| 2 | `kumamoto-station-2026-11`、`duoliang-station-2026-11`（`tw-rail-ref-landmarks-2026-11` 的多良站同一件） | 換掉遊戲自己畫的車站：要找收購真實路線時蓋站的程式，讀 `real-line-laying` 技能；熊本站要對新幹線高架 |
| 3 | `hk-dream-castle`、`hk-park-layout`、`hk-park-main-street`、`hk-park-rides`、`hk-park-zones-north`、`hk-park-zones-south`（皆 `-2026-11`） | 童話樂園整座一起擺，照 `hk-park-layout` 的配置；會轉的設施要動畫（`motion` 技能），香港地圖預算約 20,132，七件加起來先算 |
| 4 | `hk-ocean-park-landmarks-2026-11` | 摩天輪會轉、纜車要畫線 |
| 5 | `estate-amusement-park`、`estate-department-store`、`estate-hotel-tower`（皆 `-2026-11`） | 換玩家蓋的建物外觀；遊樂園要慢轉 |
| 6 | `pedestrians-2a`、`pedestrians-2b`、`scooter-old`（皆 `-2026-11`） | 路人款式池、分區權重、機車數量預算；先量效能 |
| 7 | `meshy-temple-animals-2026-11` | 寫擺在廟前哪裡的規則 |
| 8 | `viaduct-shops-2026-11` | 高架下開店的規則（另一張程式單） |
| 9 | `kumamoto-tram-lowfloor-2026-11`、`hk-peak-tram-car-2026-11` | 遊戲還沒有熊本市電、山頂纜車的路線；有路線才接 |

`tw-rail-ref-landmarks-2026-11` 裡的大佛已由 `fgs-big-buddha-2026-11` 取代，不接。

## 還要做的（素材庫那邊）

各批合併後，在 `railway-assets-private-2` 開一張 PR，把接了的模型的經驗檔「接回遊戲」一節改成已接（附遊戲 PR），並更新 `MODEL-INVENTORY.md`。
