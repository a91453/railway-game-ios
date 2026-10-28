# 私庫與素材庫資產盤點（2026-10-28）

派工單 BI。只寫文件：沒有改、也沒有刪兩個私庫的任何檔案；沒有動私庫 PR #103；沒有動歷史。
發佈板（Releases：vehicle-source-pack-2nd、vehicle-source-pack-3rd、Tai）作者說「都不動」，不列入。
作者在第 5 節勾選後，再另開一般的刪除 PR（不改歷史）。

## 0. 結論

- 兩庫現在的檔案加起來約 **4.5 GB**：`railway-reference-private`（舊庫）2,429 MB／11,709 檔，`railway-assets-private`（新庫）2,147 MB／29,561 檔。
- 新庫 **77%** 是 `game-art-previews/docs/art/`（1,652 MB／27,578 檔）。其中真正占空間的不是模型，而是**逐幀 PNG**（5 個模型各有 1,600–4,500 張）。
- 新庫 AGENTS.md 點名的三個違規（`history/`、ZIP、重檔兩處）：**`history/` 和 ZIP 已在 main 清掉**（assets #8 刪 1,285 檔 56.5 MB 與 10 個 ZIP，#10 刪 TEMU1000／TEMU2000 的 ZIP）。`asset_guard --audit` 在 main 上報 0 項；它沒查的「預覽超過每輪上限」還有 5 個模型超過，見第 4 節。
- 勾選表（第 5 節）：**可刪最多 301.7 MB**（都在新庫，都是被取代輪次的逐幀 PNG 與改之前的對照資料夾）；**要作者判斷最多約 1,200 MB**，我的傾向全照辦約省 127 MB（合計 428.7 MB）；其餘都留。
- **省的是工作樹，不是 clone**：刪除 PR 只讓 main 的檔案變少。歷史照舊，clone 大小不變（planning 的決定：先不清歷史）。刪掉的檔案都還能從 git 歷史找回。

## 1. 怎麼量的（與限制）

| 項目 | 做法 |
| --- | --- |
| 大小、檔案數 | 舊庫：main 的 depth-1 檢出，逐檔 `lstat`。新庫：GitHub 的 tree API（`git/trees/HEAD?recursive=1`，未被截斷），main `8348b26` |
| 最後 commit | 舊庫：抓到完整歷史（431 個 commit），`git log -1 -- <路徑>`。新庫：只有 20 個 commit，**全部是 2026-10-28 的搬家**，所以這欄沒有資訊；新庫資料夾的實際日期看資料夾名 |
| 引用檔數 | 在本庫（`deb2b64`）用資料夾的**完整路徑**（新庫用資料夾名）搜 `Sources/ Tests/ RailwayGameApp/ Package.swift`（程式）、`tools/ .github/ .claude/ Web/`（工具）、`docs/ README.md GoldenScenarios/ CLAUDE.md AGENTS.md`（文件）、`CLAUDE.md`。數的是「有幾個檔案提到」 |
| 「遊戲有沒有載入」 | 遊戲在執行時**不讀**任何私庫。程式引用都是註解、資料來源名單（`DataSourceCredits`）或測試裡寫的出處；真正進 App 的是 `RailwayGameApp` 打包的複本。所以「程式引用 > 0」的意思是「有打包資料或程式碼是從這裡來的」 |
| 不確定的 | 搜尋只看文字。用別的拼法、只在 PR 描述或登記留言裡提到的，搜不到 |

## 2. 舊庫 `railway-reference-private`

### 2.1 頂層與第二層

| 資料夾 | MB | 檔案數 | 最後 commit | 程式／工具／文件／CLAUDE.md 引用檔數 |
| --- | ---: | ---: | --- | --- |
| **Ci** | 57.1 | 388 | 2026-10-05 | 333／82／157／1 |
| 　Ci/reference_snapshot | 57.1 | 384 | 2026-10-05 | 20／4／45／1 |
| **MapBuilder** | 5.3 | 70 | 2026-10-08 | 31／4／35／1 |
| 　MapBuilder/reference_snapshot | 5.2 | 67 | 2026-10-08 | 3／1／11／0 |
| **OpenWorld** | 61.8 | 479 | 2026-10-10 | 10／10／40／1 |
| 　OpenWorld/reference_snapshot | 61.7 | 476 | 2026-10-10 | 3／0／25／0 |
| **Railway** | 2106.1 | 10190 | 2026-10-28 | 362／173／279／1 |
| 　Railway/city_world_reference | 24.3 | 146 | 2026-10-15 | 10／1／33／1 |
| 　Railway/commuter_journey_reference_clean | 2.2 | 270 | 2026-10-14 | 0／0／18／1 |
| 　Railway/geo-scene-reference-clean | 546.4 | 2097 | 2026-10-25 | 25／6／8／1 |
| 　Railway/island_city_reference_clean | 0.7 | 80 | 2026-10-13 | 2／0／21／1 |
| 　Railway/location_modeler_reference_clean | 3.6 | 25 | 2026-10-15 | 4／0／5／1 |
| 　Railway/night_district_reference_clean | 1.5 | 12 | 2026-10-15 | 0／0／3／1 |
| 　Railway/procedural_assets_reference_clean | 106.5 | 903 | 2026-10-15 | 1／1／4／1 |
| 　Railway/railway-asset-pipeline-2026-10-22 | 0.4 | 68 | 2026-10-25 | 1／0／3／0 |
| 　Railway/railway_game_reference_clean | 10.3 | 16 | 2026-10-07 | 5／0／24／1 |
| 　Railway/site_archive_clean | 105.1 | 344 | 2026-10-08 | 18／9／32／1 |
| 　Railway/street_scene_reference_clean | 18.5 | 16 | 2026-10-13 | 3／0／19／1 |
| 　Railway/taiwan-rail-reference-clean | 434.0 | 3449 | 2026-10-18 | 9／8／59／1 |
| 　Railway/tdx-bus-history-2026-10 | 76.2 | 14 | 2026-10-27 | 0／0／4／1 |
| 　Railway/tdx-live-2026-10 | 8.1 | 33 | 2026-10-27 | 0／0／3／0 |
| 　Railway/tdx-snapshot-2026-10 | 284.8 | 105 | 2026-10-27 | 0／2／3／1 |
| 　Railway/town-scene-reference-clean | 10.9 | 99 | 2026-10-17 | 3／0／9／1 |
| 　Railway/train_loop_reference_clean | 0.1 | 8 | 2026-10-12 | 0／0／8／1 |
| 　Railway/tw3d-reference-clean | 175.5 | 2075 | 2026-10-26 | 5／0／10／1 |
| 　Railway/world-rail-reference-clean | 297.0 | 429 | 2026-10-18 | 0／0／4／1 |
| **Simulator** | 11.0 | 99 | 2026-10-17 | 34／9／94／1 |
| 　Simulator/reference_snapshot | 11.0 | 99 | 2026-10-08 | 1／2／19／0 |
| **Website** | 39.9 | 225 | 2026-10-27 | 9／6／12／1 |
| 　Website/reviews | 0.2 | 8 | 2026-10-23 | 0／0／0／0 |
| 　Website/screenshots | 13.7 | 15 | 2026-10-12 | 0／0／0／0 |
| 　Website/site | 25.9 | 192 | 2026-10-27 | 2／2／8／0 |
| 　Website/tools | 0.0 | 9 | 2026-10-11 | 0／0／2／0 |
| **city_map_reference_clean** | 107.0 | 171 | 2026-10-16 | 2／1／7／1 |
| 　city_map_reference_clean/source | 106.3 | 157 | 2026-10-16 | 1／0／2／0 |
| **power_grid_reference_clean** | 8.0 | 83 | 2026-10-16 | 0／0／2／1 |
| 　power_grid_reference_clean/source | 7.2 | 75 | 2026-10-16 | 0／0／0／0 |

（`Railway/` 底下 19 個資料夾已全部列出；`Website/`、`city_map_reference_clean/`、`power_grid_reference_clean/` 的第二層也列了。`.github/` 只有 3 個 workflow 檔，0 MB。`Railway/ASSETS_MOVED_2026-10-28.md` 是搬家說明。）

### 2.2 逐項判斷

| 資料夾 | 判斷 | 理由 |
| --- | --- | --- |
| `Ci/`、`Simulator/`、`MapBuilder/`、`OpenWorld/` | 留 | CLAUDE.md 的參考來源清單；`Ci/reference_snapshot` 被 20 個程式檔、45 個文件引用 |
| `Railway/geo-scene-reference-clean`（546 MB，舊庫最大） | 留 | 25 個程式檔引用（地名、行政界、人口、危害資料）；大小幾乎都在 `source/public`（521 MB）資料 |
| `Railway/taiwan-rail-reference-clean`（434 MB） | 留 | CLAUDE.md 指定新工作優先用它；9 個程式檔、8 個工具引用 |
| `Railway/tw3d-reference-clean`（176 MB） | 留 | 5 個程式檔引用；NEXT_PRIORITIES §22.12 列了要取什麼 |
| `Railway/world-rail-reference-clean`（297 MB） | 留（要作者知道） | 程式與工具引用 **0**，只有 4 個文件；12 個台灣以外城市的網路與時刻表。CLAUDE.md 列為來源，現階段遊戲還沒用到。想省空間時的第一個候選，見 J9 |
| `Railway/tdx-snapshot-2026-10`（285 MB） | 留 | 0 個程式引用，2 個工具、3 個文件；341 天的誤點資料是之後做誤點模型的資料。**這是整理交通開放資料的第三方網站的下載** |
| `Railway/tdx-bus-history-2026-10`（76 MB） | 要作者判斷 | 0 個程式、0 個工具引用，4 個文件；公車位置樣本（因為不能依路線過濾而截斷）。見 J8 |
| `Railway/tdx-live-2026-10`（8 MB） | 留 | 資料表在 `TDX_LIVE_DATA_MAP_2026-10-27.md` 與 HANDOFF 提到；決策 438 的下一步要用 |
| `Railway/site_archive_clean`（105 MB） | 要作者判斷（現在不要刪） | **已被 `taiwan-rail-reference-clean` 取代**（CLAUDE.md 這樣寫），其中約 59.7 MB 的檔案與新資料夾位元組相同。但 18 個程式檔、9 個工具（`tools/real-timetables`、`tools/real-railways`、`tools/real-world-population`）的來源註解與腳本仍寫這個路徑。見 J7 |
| `Railway/procedural_assets_reference_clean`（106 MB） | 留 | 1 個程式引用（註解）、4 個文件；CLAUDE.md 列為來源。第二個候選，見 J11 |
| `Railway/city_world_reference`（24 MB）、`commuter_journey_reference_clean`、`island_city_reference_clean`、`location_modeler_reference_clean`、`night_district_reference_clean`、`railway_game_reference_clean`、`street_scene_reference_clean`、`town-scene-reference-clean`、`train_loop_reference_clean` | 留 | 全部在 CLAUDE.md 的來源清單，加起來 73 MB；多半只被文件引用，但小 |
| `Railway/railway-asset-pipeline-2026-10-22`（0.4 MB） | 留 | `Map3DDepotFacilities.swift` 與決策 441 的對照表引用 |
| `city_map_reference_clean`（107 MB）、`power_grid_reference_clean`（9 MB） | 留 | CLAUDE.md 列為來源 |
| `Website/site`（26 MB）、`Website/tools` | 留 | 官網的部署來源（Cloudflare Pages 的上傳資料夾），不是參考資料 |
| `Website/screenshots`（13.7 MB）、`Website/reviews`（0.2 MB） | 要作者判斷 | 改版面前後對照的截圖；0 個引用。見 J10 |

### 2.3 重複

舊庫內位元組相同、超過 200 KB 的檔案，多出來的部分共 **78.5 MB**：`site_archive_clean`↔`taiwan-rail-reference-clean` 46.4 MB（再加三者相同 13.3 MB）、`OpenWorld` 內部 10.6 MB、`taiwan-rail` 內部 3.4 MB、`Ci` 內部 2.8 MB。除了第一組（見 J7），其他是來源本身的重複，不建議動。

## 3. 新庫 `railway-assets-private`

### 3.1 頂層與第二層

（最後 commit 欄全是搬家日 2026-10-28，沒有資訊。）

| 資料夾 | MB | 檔案數 | 最後 commit | 引用檔數（程式／工具／文件） |
| --- | ---: | ---: | --- | --- |
| **game-art-previews** | 1653.8 | 27584 | 2026-10-28 | 7／31／111 |
| 　game-art-previews/docs | 1652.3 | 27578 | 2026-10-28 | –／–／– |
| 　game-art-previews/tools | 1.5 | 2 | 2026-10-28 | –／–／– |
| **meshy-batch-2026-10** | 277.7 | 92 | 2026-10-28 | 1／2／3 |
| 　meshy-batch-2026-10/glb | 36.1 | 17 | 2026-10-28 | –／–／– |
| 　meshy-batch-2026-10/glb-hq | 203.9 | 17 | 2026-10-28 | 0／0／1 |
| 　meshy-batch-2026-10/glb-lod | 32.5 | 2 | 2026-10-28 | 0／1／1 |
| 　meshy-batch-2026-10/previews | 4.9 | 45 | 2026-10-28 | –／–／– |
| **n700s-n700st-2026-10-24** | 125.5 | 303 | 2026-10-28 | 2／3／5 |
| 　n700s-n700st-2026-10-24/inputs | 0.5 | 6 | 2026-10-28 | –／–／– |
| 　n700s-n700st-2026-10-24/n700s | 40.4 | 75 | 2026-10-28 | –／–／– |
| 　n700s-n700st-2026-10-24/n700s-g | 40.3 | 73 | 2026-10-28 | –／–／– |
| 　n700s-n700st-2026-10-24/n700st | 40.4 | 73 | 2026-10-28 | –／–／– |
| 　n700s-n700st-2026-10-24/source-body | 3.8 | 71 | 2026-10-28 | –／–／– |
| **generated-3d-assets-2026-10-21** | 90.2 | 1576 | 2026-10-28 | 0／0／3 |
| 　generated-3d-assets-2026-10-21/scene-kit-pr900 | 77.0 | 1486 | 2026-10-28 | 0／0／2 |
| 　generated-3d-assets-2026-10-21/trains-pr901 | 13.2 | 88 | 2026-10-28 | 0／2／1 |

另外有 `README.md`、`AGENTS.md`、`CLAUDE.md`、`tools/asset_guard.py`、`.github/workflows/asset-guard.yml`，合計小於 0.1 MB。

### 3.2 `game-art-previews/docs/art/` 的 94 個模型資料夾

大於 5 MB 的全列。PNG 欄是檔案數；「輪次資料夾」是 `revision-N`、`candidate-N`、`final` 的個數。

| 模型資料夾 | MB | 檔案 | PNG | 輪次資料夾 | 引用檔（程式／工具／文件） |
| --- | ---: | ---: | ---: | --- | --- |
| emu900-native-2026-10-27 | 168.6 | 3389 | 3224 | 4 | 0／1／2 |
| station-kit-2026-10-21 | 138.1 | 5794 | 4505 | – | 0／2／4 |
| taipei610-2026-10-27 | 132.5 | 2184 | 1938 | 8 | 0／0／2 |
| emu3000-refresh-2026-10-25 | 124.4 | 1772 | 1596 | 5 | 0／3／4 |
| emu3000-slate-2026-10-27 | 104.2 | 951 | 418 | – | 0／2／2 |
| emu800-native-2026-10-27 | 91.6 | 663 | 538 | 1 | 0／1／1 |
| pp-coaches-2026-10-26 | 90.1 | 401 | 321 | – | 0／2／2 |
| train-occlusion-439 | 73.6 | 2961 | 2960 | – | 0／0／2 |
| chukuang-coaches-2026-10-26 | 62.4 | 721 | 611 | 1 | 0／2／2 |
| train-shape-refresh-2026-10-24 | 60.1 | 414 | 351 | 9 | 0／0／4 |
| map3d-fresnel-2026-10-22 | 33.8 | 29 | 28 | – | 0／0／2 |
| generated-2026-10-13 | 33.4 | 55 | 52 | – | 0／0／7 |
| emu500-2026-10-27 | 33.0 | 725 | 636 | 8 | 0／0／2 |
| map3d-sun-shadow-2026-10-22 | 28.2 | 23 | 21 | – | 0／0／2 |
| generated-2026-10-14-micro3d | 28.1 | 37 | 34 | – | 0／0／3 |
| map3d-signs-2026-10-22 | 27.3 | 26 | 25 | – | 0／0／2 |
| c341-native-2026-10-27 | 25.8 | 382 | 314 | 4 | 0／0／1 |
| e500-refresh-2026-10-25 | 24.9 | 532 | 431 | 2 | 0／3／2 |
| works-kit-2026-10-21 | 23.4 | 497 | 385 | – | 0／1／1 |
| steam-tender-2026-10-23 | 18.7 | 188 | 137 | – | 0／1／2 |
| train-colors-2026-10-22 | 17.3 | 222 | 178 | – | 0／1／5 |
| duplex-steam-2026-10-23 | 16.9 | 174 | 131 | – | 0／1／2 |
| detail-kit-2026-10-21 | 15.9 | 1160 | 852 | – | 0／2／1 |
| seven-car-blue-2026-10-23 | 15.3 | 187 | 150 | – | 0／1／2 |
| estate-kit-2026-10-23 | 14.8 | 311 | 235 | – | 0／2／1 |
| lrt-pair-2026-10-22 | 13.9 | 248 | 189 | – | 0／1／3 |
| train-modeling-410 | 13.2 | 88 | 87 | – | 0／5／3 |
| 3d-style-2026-10-13 | 12.6 | 57 | 0 | – | 4／1／5 |
| railway-ui-redesign-2026-10-14 | 11.9 | 14 | 13 | – | 5／0／5 |
| screen-shell-2026-10-14 | 11.1 | 11 | 10 | – | 0／0／4 |
| map3d-footprints-2026-10-23 | 10.8 | 13 | 12 | – | 0／0／1 |
| four-car-metro-2026-10-23 | 10.0 | 134 | 106 | – | 0／2／2 |
| hsr-trains-408 | 9.8 | 123 | 122 | – | 3／5／5 |
| park-kit-2026-10-21 | 9.7 | 388 | 300 | – | 0／1／3 |
| civic-kit-2026-10-21 | 9.0 | 496 | 384 | – | 0／1／2 |
| three-car-urban-2026-10-22 | 8.8 | 113 | 80 | – | 0／1／3 |
| recreation-kit-2026-10-23 | 8.7 | 318 | 240 | – | 0／2／1 |
| commercial-kit-2026-10-21 | 8.7 | 388 | 300 | – | 0／1／2 |
| map3d-mapbox-look-2026-10-23 | 8.4 | 43 | 0 | – | 2／0／5 |
| garbage-truck-2026-10-27 | 7.3 | 6 | 4 | – | 0／0／1 |
| temu2000-2026-10-26 | 6.5 | 108 | 84 | – | 0／1／1 |
| residential-kit-2026-10-21 | 6.2 | 279 | 216 | – | 0／3／1 |
| viaduct-kinds-2026-10-25 | 6.1 | 8 | 7 | – | 0／0／2 |
| coastal-kit-2026-10-23 | 6.0 | 293 | 222 | – | 0／3／1 |
| airline-ui-borrow-2026-10-14 | 5.9 | 7 | 6 | – | 1／0／4 |
| temu1000-2026-10-25 | 5.7 | 93 | 70 | – | 0／1／3 |
| map3d-road-markings-2026-10-22 | 5.7 | 11 | 10 | – | 0／0／2 |
| map3d-no-build-2026-10-23 | 5.6 | 9 | 8 | – | 0／0／2 |
| 其餘 46 個小資料夾（各小於 5 MB，多為 map3d-* 與舊介面預覽） | 48.2 | 532 | | | 多為 0／0／1–4 |

遊戲庫的 `docs/art/` 對應資料夾（共 54 MB）留著 README 與定案圖，所以**刪新庫的某一輪預覽不會讓遊戲庫的文件連結壞掉**；刪的只是作者回頭看的那份完整預覽。

### 3.3 逐項判斷

| 項目 | 判斷 | 理由 |
| --- | --- | --- |
| `game-art-previews/docs/art/*` 的最新一輪（`final`、最大編號的 `revision-N`、`models/`） | 留 | AGENTS.md 規則 1：最新一輪留模型與 viewer |
| `inputs/`、`producer-source/`、`sources/`、`reference-record/`、`evidence/` | 留 | 規則 6：能重建的 commit、指令、來源與授權 |
| `meshy-batch-2026-10/`（278 MB） | 見 J1、J2 | 還沒接進遊戲；重生要花 Meshy 點數（每個模型 15 點） |
| `n700s-n700st-2026-10-24/`（126 MB） | 見 J4 | 遊戲庫的 `tools/n700s-n700st/` 是公開配方；三個變體各有 29 MB 的離線 viewer |
| `generated-3d-assets-2026-10-21/`（90 MB） | 見 J3 | `scene-kit-pr900` 是 Codex 生成的素材表；遊戲只用 Swift 程式，不讀這些檔 |
| 其餘 `map3d-*`、介面預覽（各小於 5 MB 的 60 個以上資料夾，合計約 40 MB） | 留 | 小、被文件引用（1–4 個檔） |

## 4. 違反 railway-assets-private AGENTS.md 的現況（只列，不清）

AGENTS.md 的規則，對 main `8348b26` 逐條對照（`python3 tools/asset_guard.py --audit` 在 main 上報 **0 項違規**，因為它只查規則 4「同一模型有多個輪次資料夾放重檔」；下面是它沒查的部分，我自己算的）：

| 規則 | 現況 | 數字 |
| --- | --- | --- |
| 2 不放 `history/`、`old/`、`backup/`；不放 ZIP | **已清**。main 上這類路徑與 `.zip`、`.7z`、`.tar`、`.mp4`、`.mov` 都是 0。歷史裡仍有 | assets #8（1,285 檔、56.5 MB、10 個 ZIP）、#10（TEMU1000／TEMU2000 的 ZIP） |
| 1 只有最新一輪留重檔 | guard 報 0，我也沒找到兩個輪次同時留重檔的模型（重檔都在 `final`、最大編號的 `revision-N` 或模型頂層）。字面上「重檔在頂層與 `models/` 兩處」有 11 個模型：頂層是單檔離線 viewer（內含模型），`models/` 是可再匯入的 GLB／M3DM。規則 1 允許最新一輪兩者都留，所以我不算它違規，只在 J5 列給作者 | emu3000-slate（viewer 52.6／models 27.7 MB）、pp-coaches（50.1／25.7）、chukuang-coaches（26.6／14.2）、e500-refresh（6.4／4.2）；另 7 個中小型（steam-tender、train-colors、duplex-steam、seven-car-blue、lrt-pair、four-car-metro、three-car-urban）合計 41.4／26.1 MB |
| 3 每輪預覽最多 7 向 × 3 狀態（21 張），不放逐幀序列 | 超過的有 5 個模型：emu900-native 3,224 張 PNG、station-kit 4,505、train-occlusion-439 2,960、taipei610 1,938、emu3000-refresh 1,596。另有 3 張單檔超過規則 3 的 2 MB（`map3d-sun-shadow-2026-10-22`、`screen-shell-2026-10-14`、`viaduct-kinds-2026-10-25` 各 1 張） | 5 個模型合計 14,223 張、約 272 MB |
| 4 單檔 ≤ 50 MB、一個 PR ≤ 200 MB | 單檔最大 47.2 MB（`emu3000-slate-2026-10-27/viewer-standalone.html`），沒有超過。搬家四批是 501／676／650／653 MB（搬家，不是新增，作者合並） | – |
| 5 候選最多 3 個 | `taipei610-2026-10-27` 有 `candidate-1` 到 `candidate-6` 加 4 個命名候選資料夾（只有 PNG）；`emu900-native` 有 3 個候選資料夾 | 候選 PNG 約 48 MB |

## 5. 勾選表

「MB」是**刪掉後 main 的工作樹少多少**（上限；有些列說明可以改成只留 21 張）。clone 大小不變。勾選後另開一般的刪除 PR，不改歷史。

### 5.1 可刪（建議刪）

| ✓ | 編號 | 路徑（新庫 `railway-assets-private`） | 可省 MB | 理由 |
| --- | --- | --- | ---: | --- |
| ☐ | D1 | 被取代輪次與候選的逐幀 PNG（下面 7 列合計）：<br>`emu900-native-2026-10-27/` 的 `candidate-1`、`candidate-2`、`revision-2`、`revision-2-candidate-1`（65.3）<br>`taipei610-2026-10-27/` 的 `candidate-*`、`revision-1`、`revision-2-candidate-window-ties`（48.9）<br>`emu3000-refresh-2026-10-25/revision-1` 到 `revision-4`（38.7）<br>`emu500-2026-10-27/revision-1` 到 `revision-7`（16.7）<br>`train-shape-refresh-2026-10-24/revision-2` 到 `revision-9`（10.5）<br>`c341-native-2026-10-27/revision-1` 到 `revision-3`（7.0）<br>`e500-refresh-2026-10-25/revision-2`（5.4） | 192.5 | 重檔早就在 2026-10-28 的整理裡拿掉，只剩逐幀 PNG；各模型都有更新的輪次；規則 3 不准逐幀序列。若想留個紀錄，每輪留 ≤ 21 張，約省 85% |
| ☐ | D2 | `station-kit-2026-10-21/views/`（4,487 張七向 PNG） | 29.4 | 技能 `station-kit` 可以重新匯出；`previews/`（18 張）與 `models/` 留著 |
| ☐ | D3 | `train-occlusion-439/after/`（2,926 張）與 `stronger/` | 72.7 | 決策 439 的遮擋修正前後逐幀；結論在決策與遊戲庫的 `docs/art/train-occlusion-439/`。若要留證據，留 ≤ 21 張，約省 70 |
| ☐ | D4 | `five-section-lrt-2026-10-22-before`、`-initial`；`three-car-urban-2026-10-22-initial`；`four-car-metro-2026-10-23-initial`；`train-colors-2026-10-22-before` | 7.1 | 同一模型的「改之前」資料夾，規則 1 要一個模型一個資料夾；文件引用 0–1 個；`four-car-metro-2026-10-23-initial` 與 `train-colors-2026-10-22-before` 各有 1 個工具檔提到，刪前要一起改 |
| | | **可刪合計** | **301.7** | |

### 5.2 要作者判斷

| ✓留 | ✓刪 | 編號 | 路徑 | 可省 MB | 兩邊的理由（我的傾向） |
| --- | --- | --- | --- | ---: | --- |
| ☐ | ☐ | J1 | 新庫 `meshy-batch-2026-10/glb-hq/`（17 檔） | 203.9 | 留：README 說這組是「建議用這組」，之後要接進遊戲；重生一個模型 15 點。刪：還沒接進遊戲，檔案很大。**傾向：留** |
| ☐ | ☐ | J2 | 新庫 `meshy-batch-2026-10/glb/`（17 檔） | 36.1 | 第一組低面數，README 自己寫「已被第二組取代，留作對照」。**傾向：刪** |
| ☐ | ☐ | J3 | 新庫 `generated-3d-assets-2026-10-21/scene-kit-pr900/`（1,486 檔） | 77.0 | 遊戲只用程式幾何，不讀這些檔；原始 commit `f44e62d` 還在遊戲庫的 PR #900 與 `codex/taiwan-scene-assets-2026-10-21` 分支上。刪的風險：那個分支被清掉就找不回。**傾向：刪** |
| ☐ | ☐ | J4 | 新庫 `n700s-n700st-2026-10-24/` 的三個離線 viewer：`n700s/Railway_N700S_Viewer.html`、`n700st/…`、`n700s-g/…`（各 29 MB） | 87.0 | 公開配方 `tools/n700s-n700st/` 能重建；但規則 1 允許最新一輪留 viewer，作者也用它離線看。**傾向：留** |
| ☐ | ☐ | J5 | 新庫 4 個大模型的頂層 viewer 與 `models/`（見第 4 節）：只留其中一種 | 刪 `models/` 約 71.8；或刪頂層 viewer 約 135.7 | viewer 單檔、可離線開、已含模型；`models/` 的 GLB／M3DM 才是能再匯入的原檔。規則 1 允許兩者都留。**傾向：留**（不省） |
| ☐ | ☐ | J6 | 新庫 `generated-2026-10-13/`（33.4）、`generated-2026-10-14-micro3d/`（28.1） | 61.5 | AI 生成的素材表；遊戲庫留 README 與 manifest。很久沒人用（文件引用 7、3 個檔）。**傾向：留**，等作者說不要 |
| ☐ | ☐ | J7 | 舊庫 `Railway/site_archive_clean/` | 105.1（只刪與新資料夾相同的檔，約 59.7） | 已被 `taiwan-rail-reference-clean` 取代，但 18 個程式檔、9 個工具還指它。**傾向：現在不刪**；先另派一張單把這些註解與腳本的來源路徑改到新資料夾，再刪 |
| ☐ | ☐ | J8 | 舊庫 `Railway/tdx-bus-history-2026-10/` | 76.2 | 0 個程式與工具引用；是截斷的公車位置樣本。刪：樣本不完整。留：之後做公車需求或班表時要對照。**傾向：留**（決策 438 的下一步還沒做） |
| ☐ | ☐ | J9 | 舊庫 `Railway/world-rail-reference-clean/` | 297.0 | 12 個台灣以外城市的網路與時刻表，0 個程式與工具引用。刪：遊戲目前只做台灣。留：CLAUDE.md 列為來源，「國際版」在長期目標裡。**傾向：留**，要省空間時它是最大的一塊 |
| ☐ | ☐ | J10 | 舊庫 `Website/screenshots/`、`Website/reviews/` | 13.9 | 改官網版面時的前後截圖，0 個引用，與官網部署無關。**傾向：刪** |
| ☐ | ☐ | J11 | 舊庫 `Railway/procedural_assets_reference_clean/` | 106.5 | 只有 1 個程式檔（註解）、4 個文件提到。**傾向：留**（CLAUDE.md 列為來源，3D 配方還在參考它） |
| | | | **判斷合計（上限）** | 約 **1,200** | 傾向「刪」的只有 J2 36.1＋J3 77.0＋J10 13.9＝**127.0 MB**；加上第 5.1 節 301.7，全照傾向約 **428.7 MB** |

> J4 與 J5 不重疊（`n700s-n700st` 不在 J5 的 4 個模型內）。判斷合計 ＝ J1 203.9＋J2 36.1＋J3 77.0＋J4 87.0＋J5 135.7＋J6 61.5＋J7 105.1＋J8 76.2＋J9 297.0＋J10 13.9＋J11 106.5 ＝ 1,199.9。

### 5.3 留（不用勾）

- 舊庫：`Ci/`、`Simulator/`、`MapBuilder/`、`OpenWorld/`、`Railway/` 其餘全部、`city_map_reference_clean/`、`power_grid_reference_clean/`、`Website/site/`、`Website/tools/`、`.github/`、`AGENTS.md`。
- 新庫：各模型最新一輪與 `models/`、`inputs/`、`producer-source/`、`sources/`、`reference-record/`、`evidence/`、`meshy-batch-2026-10/glb-lod/` 與 `previews/`、`generated-3d-assets-2026-10-21/trains-pr901/`、所有 README／SOURCE／`tools/`、`asset_guard`。
- 發佈板：不動。
- 歷史：不改（planning 2026-10-28 的決定；改寫會讓 #103 這類分支與文件裡的 commit 引用失效）。

## 6. 作者勾完之後

1. 勾 D1–D4 與 J1–J11 各一欄，回在 #1041。
2. 開一般的刪除 PR（新庫一張；舊庫若要動 J7–J11 另一張）。不用 force-push，不用 `filter-repo`。
3. 新庫的刪除 PR 要過 `asset-guard`；D1、D2、D3 是在減少規則 3 的違規；`asset_guard` 看的是 PR 新增，刪檔不會變紅。
4. J7 先另派一張：把 `tools/real-timetables`、`tools/real-railways`、`tools/real-world-population` 與 18 個 Swift 檔註解的 `site_archive_clean` 路徑改到 `taiwan-rail-reference-clean`（對照每個檔案是否真的有對應檔），再刪舊目錄。
5. 再做一次本盤點時，加一欄「刪了以後哪個 commit 還能找回」，並把 `asset_guard.py --audit` 加上規則 1（重檔放一處）與規則 3（預覽張數）的檢查，兩者目前只靠人看。

## 7. 查過什麼

- 舊庫與新庫的 `AGENTS.md`、`README.md`、`00_READ_ME_FIRST.md`、本庫 `CLAUDE.md` 的來源清單。
- #1041 最近 209 則留言（未釋出的登記）：沒有別的登記動這兩個私庫或 `docs/research/`。
- 這張單沒有參考對照表可附：沒有搬或改任何程式與資料（參考庫：已全部讀過目錄；對外的開源專案：無，這是盤點）。
- 沒做的：沒下載新庫的檔案內容（只讀 tree API 的大小與幾個 README）；沒開任何一個 PNG 看內容；「引用檔數」只看文字。**UNVERIFIED**：PR 描述或登記留言裡才提到的引用；各模型逐幀 PNG 是否全是逐幀（只用檔數與資料夾名判斷）。

## 8. 五方

- 玩家：沒有影響；盤點不碰 App 與遊戲內容。
- 鐵道迷：資料來源與取代關係（`site_archive_clean`→`taiwan-rail-reference-clean`）一個都不動，等工具改完路徑才可刪，不會讓出處註解變成空路徑。
- 開發：新庫 main 約有 300 MB 是被取代的預覽，刪掉讓 clone 與搜尋都輕一點；工作樹會小，clone 要等歷史才縮，這次不做。
- 美術：每個模型的最新一輪與模型本身都留；被刪的只有逐幀序列，要的時候可以用技能重新匯出，或從 git 歷史找回。
- 音樂：無。
