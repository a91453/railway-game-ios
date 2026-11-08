# 哪些東西已經比現實或上游舊（STALE-AUDIT，2026-11-08）

派工單 STALE-AUDIT（`claude/stale-audit`，遊戲規劃第 56 任派）。只盤點，沒有升級任何東西；存檔、golden、GameCore、決策號都不動。

查證方法與限制（讀之前先看）：

- 上游版本與更新說明來自各專案的 GitHub releases 頁（這個 session 的 GitHub 工具只開放本專案，所以用網頁讀）。日期是頁面上寫的發佈日。
- iOS 警告來自 main 最近一次綠的兩個 run 的 job log：`ios-build.yml`「Xcode build (iOS Simulator)」（run 42383676242，2026-11-07，Xcode 26.6）與 `release-archive.yml`「Release archive」（run 42420029196，2026-11-07，Xcode 26.6）。
- 真實世界的新聞（改點、通車）來自網路搜尋，沒有一條讀過官方公告原文，**標「待查」的不要當成事實**。
- 「建議」欄：**更新**＝值得做；**不急**＝可以排後面；**不更新**＝有理由留著。

---

## 1. 外部依賴

| 項目 | 現在用的 | 最新的 | 差多少 | 建議與理由 |
|---|---|---|---|---|
| MapLibre Native（`RailwayGameApp/project.yml`，`exactVersion: 6.31.0`） | 6.31.0（2026-09-11） | 7.0.0（2026-10-28）；另有 2026.10.19-globe、2026.11.2-globe（globe 投影版） | 6 個較新的發佈（7.0.0-pre0／pre-globe.0／pre2、7.0.0、兩個 globe 版） | **不急。** 7.0.0 是破壞性更新：最低 iOS 升到 15.5（本專案 deploymentTarget 17.0，沒影響）、`Mapbox.h` 換成 `MapLibre.h`（Swift 不用改，Objective-C 引用要改；本專案是 Swift）、`MapboxVersionNumber/String` 沒了、獨立的 iOS 除錯符號 ZIP 不再發。修的是兩個崩潰（影像來源整個超出緯度上限 #4753、自訂幾何來源在第一塊圖磚前被查詢 #4718）和動態紋理釋放的競態（#4817）。發佈說明裡**看不到安全修正**。我們的地圖用 PMTiles 與自家圖層，要先確認有沒有走到上述兩個崩潰路徑再決定。6.31.0 本身已移除 `CustomDrawableLayer`，本專案若沒用就沒事。升級要整個 3D／2D 地圖在 macOS 實機驗，Linux 驗不了。 |
| XcodeGen（`.github/actions/setup-xcodegen/action.yml`） | 2.46.0（2026-09-13） | 2.46.0 | 0，是最新 | **不更新。** 2.46.0 的預設變動（靜態 framework 預設嵌入、target 保持 spec 宣告順序）已經在目前的 committed 專案裡。 |
| Swift（CI `swift:6.4-noble`；macOS 的 `release-archive` 與 `testflight` 另下載 `swift-6.4.0-RELEASE-osx.pkg`） | 6.4.0 | 6.4.2（2026-10-30，網頁上無說明文字）；6.4.1 的日期查不到 | 差兩個修正版 | **不急。** CLAUDE.md 規定「只用 Swift 6.4」；6.4.x 是同一個大版本的修正版，升之前要 `.claude/hooks/session-start.sh`、`ci.yml` 的 `swift:6.4-noble` 容器、兩個 macOS workflow 的 `.pkg` 網址一起改，且要看 6.4.1／6.4.2 修了什麼（說明查不到）。 |
| macOS runner | `macos-26`（9 處） | `macos-26` 是最新；`macos-latest` 也指向 macOS 26（macOS 26.6.2，image 20261026） | 0 | **不更新。** macOS 14 的 image 已在 2026-11-02 退役；本專案已經是 26，不受影響。Xcode 27 在 runner-images 上標為 preview。 |
| Xcode | 26.6（runner 預設，兩個 log 都是 Xcode 26.6，Build 17F113） | 26.6 是預設；另裝 26.5、26.4.1、26.3 … | 0 | **不更新。** 等 Xcode 27 正式（目前 preview）再說；到時 OpenSSL 預設由 3 變 4，可能影響 runner 上用到 openssl 的腳本（待確認）。 |
| Linux runner | `ubuntu-24.04`（18 處）、`ubuntu-latest`（4 處） | runner-images 同時有 24.04 與 26.04 | 24.04 沒有看到退役公告 | **不急。** `ubuntu-latest` 的 4 處哪天會被換成 26.04，建議之後一起固定成 `ubuntu-24.04`，免得無預警換版（本次未查 Announcement 議題）。 |
| `actions/checkout` | `@v7`（10）、`@v5`（10）、`@v6`（1）、固定 SHA（7） | v7.0.1（2026-07-20）；v6.1.0、v5.1.0 也在同日發出 | 同時用三個大版本加固定 SHA | **不急。** v6.1.0、v5.1.0 標為 BREAKING（回補 `allow-unsafe-pr-checkout`，也就是 `pull_request_target` 檢出 PR 程式碼的預設變嚴）。本專案若沒有 `pull_request_target` 檢出 PR 的 workflow 就沒事——**建議查一次**（`grep -rn pull_request_target .github`）。要統一就統一到 v7。 |
| `actions/upload-artifact` | v7（17） | v7.0.2（2026-10-07） | 修正版 | **不更新。** v7.0.2 只是 HTTP 429 重試變好；浮動 `v7` 標籤會跟著。 |
| `actions/download-artifact` | v8（2） | v8.0.2（2026-10-07） | 修正版 | **不更新。** v8.0.0 起「摘要不符就失敗」是預設，已經在用。 |
| `actions/cache`（`save`／`restore`） | v4（各 2） | v6.1.0（2026-06-26）；v5.1.0 | 落後兩個大版本 | **不急。** v5 起執行環境是 Node 24（需要 runner 2.327.1 以上，GitHub 託管的 runner 都符合）；v6 是 ESM 改寫。v5.0.3／5.0.4 有相依套件的安全修正（Dependabot alert），所以值得排進一次 workflow 維護，順便看 v4 還有沒有被停用的公告（本次沒讀到）。 |
| `actions/setup-node` | v4（2） | v7.1.0（2026-10-08） | 落後三個大版本 | **不急。** 6.5.0 有 `undici`／`fast-xml-parser` 的安全覆寫，同樣值得跟 cache 一起排。 |
| `anthropics/claude-code-action` | `@v1` | v1.0.269（2026-11-06） | 浮動標籤，自動跟上 | **不更新。** |
| iOS 部署目標 | 17.0 | — | — | 不更新。MapLibre 7 要 15.5，滿足。 |

---

## 2. iOS 淘汰警告

來源是兩個 run 的完整 job log（`gh api …/jobs/<id>/logs`）。搜尋字串：`warning`、`deprecat`、`will be removed`、`obsolete`、`no longer`。**兩個 run 的 Swift 編譯本身沒有出現 `warning:` 或 deprecation 行**（`xcodebuild` 輸出被 CI 壓成精簡版，若有編譯警告會在這裡出現；Linux 那邊的 `-warnings-as-errors` 只管 GameCore／GamePresentation，不涵蓋 `RailwayGameApp/Views` 的 SwiftUI 檔，那些只在 macOS 編譯）。所以出現的全部整理如下：

| 檔／來源 | 警告內容 | 影響估計 | 建議 |
|---|---|---|---|
| App 的 target（`appintentsmetadataprocessor`，兩個 run 各一或二次） | `Metadata extraction skipped. No AppIntents.framework dependency found.` | **無。** App 沒用 App Intents（捷徑、Siri），Xcode 只是說跳過。不是淘汰警告。 | 不更新。 |
| `release-archive.yml` 的隱私清單檢查（`::warning::The binary references APIs that may need a privacy manifest`） | 列出 `SwiftUI.AppStorage…`（`@AppStorage` 的 store 初始化）與 `_OBJC_CLASS_$_NSUserDefaults`。 | **無實際影響，是檢查腳本的提示。** `RailwayGameApp/Resources/PrivacyInfo.xcprivacy` 已宣告 `NSPrivacyAccessedAPICategoryUserDefaults`（理由 CA92.1，只讀寫 App 自己的設定）。上架時 App Store Connect 只在**沒有**宣告時才擋。 | 不更新。若想讓警告消失，可讓腳本認得已宣告的類別（工具改動，不是 App）。 |
| `ios-build.yml`、`xcodebuild` 目的地 | `--- xcodebuild: WARNING: Using the first of multiple matching destinations` | **無。** 模擬器有多個同名目的地，取第一個；與淘汰無關。 | 不急。可在 `-destination` 指定 `id=` 讓它安靜。 |
| `git`（兩個 run 的檢出步驟） | `hint: to use in all of your new repositories, which will suppress this warning` | **無。** 是 git 對預設分支名稱的提示。 | 不更新。 |
| Actions 註記 | 「Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.」 | 只影響排隊時間。 | 不更新。 |
| 其他 | `deprecated`、`Node.js 20`、`will be removed`、`obsolete`、`no longer` 在兩個 log 都是 0 次 | 目前這兩個 run 沒有 action 的 Node 20 淘汰提示。 | — |

**重點**：這個倉庫目前沒有 iOS 淘汰警告可修。以下風險在 log 裡看不到，但**待查**（Linux 查不到，要 macOS 看編譯輸出）：

- SwiftUI 檔（`RailwayGameApp/Views`）在 Xcode 26.6 下有沒有 `deprecated` 警告，要在 macOS 用不壓縮輸出的 `xcodebuild` 重跑一次才知道（建議用 `ios-build.yml` 手動跑一次、把完整輸出存成 artifact）。
- Xcode 27（預覽中）的淘汰清單，等它正式發佈再看。

---

## 3. 真實資料的新舊

「抓取日」是資料檔或工具 README 寫的日期；「上游有沒有改」除非另外標示，都是**待查**（沒讀官方公告）。表末附「訂閱結束前建議重抓」。

| 資料（App 內檔案） | 內容的日期／版本 | 出處（provenance） | 上游已知改動 | 建議 |
|---|---|---|---|---|
| **台鐵時刻表** `RealRailways/tra-schedule.json` | `tra_schedule_dense.json`，**2026-10-16 起 14 天**，取 2026-10-18 起八天 | 臺鐵開放資料 ods.railway.gov.tw，政府資料開放授權條款第 1 版（經參考庫 `taiwan-rail-reference-clean`，`tools/real-timetables/extract_tra_schedule.py`） | 搜尋沒找到 2026 年 11、12 月改點的公告（2025-12-23 有過 111 列次微調）。**但台南鐵路地下化第一階段在 10 月中旬通車（報導說 10-17 或 10-18，新台南車站同步啟用，**待查**），時刻表可能在那前後改過**。 | **值得重抓**（見下）。 |
| 台鐵宜蘭線示範 `tra-yilan-schedule.json` | 2026-10-05（舊 `site_archive_clean` 的時刻表） | 同上，舊快照 | README 自己寫：新版同名檔是 2026-10-16 的新時刻表，與打包的不同 | 不急；改用新快照重產即可，但同樣要等新抓。 |
| 台鐵平溪線等 `tra_pingxi_runs.json`、`tra_branch_runs.json` | 取自 2026-10-02 到 10-08 的第一週 | 同上舊快照 | 同上 | 不急。 |
| **高鐵時刻表** `thsr-schedule.json` | **2026-09-29** 當日逐車次 | 交通部 TDX `Rail/THSR/DailyTimetable/TrainDate` | 高鐵「新世代班表」預計 2026 年第四季公告、**2027 年初實施**（「一次改點、五次增班」，南北超級直達車、雲嘉直達台中台北）；N700ST 12 組 2027-07-01 起上線，之後才檢討票價（報導，**待查**官方）。2026-04-27 起取消 95 折團體票、尖峰全額。 | 現在**不用重抓**（新班表尚未實施）；新班表公告後再抓。 |
| 台北捷運等各站時刻 `trtc_times.json`、`krtc_times.json`、`tymc_times.json`、`ntdlrt_times.json`、`ntalrt_times.json`、`sanying_times.json` | **2026-07-16** 抓（只讀了 trtc 的 `source_notes`；其他系統的日期沒逐一讀，**待查**） | 交通部 TDX，政府資料開放授權條款第 1 版 | 桃園捷運**綠線**預計 2026 年底先通北段 7 站（G11 藝文特區—G15b 坑口），確切日期待公布（**待查**）；2026-08-30 廣慈／奉天宮已通車，已在運量註記中處理。 | 綠線通車後才有資料可抓；現有時刻不急。 |
| 台鐵車站資訊 `tra_station_info.json`、`tra.json`（245 站節點） | `tra.json`：OSM／Overpass（日期未標，約 2026-10 初）；與 TDX 2026-10-20 站表對過，245 對 245 | OSM（ODbL）、台鐵開放資料 | 台南地下化後，台南站變地下車站（林森站、南台南站 2029、2030 年才通車）；新站座標與月台資料可能和舊 OSM 不同（**待查**） | **值得重抓**台南一帶（見下）。 |
| 路線形狀與結構 `track_lines.geojson`、`track_stations.geojson`、`rail_structures.json`、`rail_tracks.json` | 形狀是作者 `Railway/` 網站的原檔（TDX）；OSM 比對用 2026-10-10 的整包檔（OSM 到 2026-10-08）；結構取自 `taiwan-rail-reference-clean`（2026-10-18 加入，含官方橋隧修正） | TDX、OSM（ODbL）、官方 | 台南地下化：原地面線台南段已被取代（**待查**）。 | 台南段建議重抓，其餘不急。 |
| 運量 `tra_ridership.json`、`thsr_ridership.json`、`trtc_ridership.json`、`krtc_ridership.json`、`tymc_ridership.json`、輕軌系列 | **2025 年**（最近一個完整年度），2026-10-20 下載；台鐵檔資料集頁 2026-10-20 時最後修改 2026-03-17，最新年檔到 2025-12-31 | data.gov.tw（台鐵、台北捷運）、台灣高鐵公司網站（高鐵）、各捷運公司 | 2026 全年數字要到 2027 才有 | 不更新；等 2026 年資料 2027 年出再換。 |
| 人口 `RealWorld/taiwan_population.json` | WorldPop **R2025A v1，Taiwan 2025**，1 km 格，GeoTIFF 2026-10-05 下載 | WorldPop，CC BY 4.0 | 下一版（R2026）尚未見 | 不更新。 |
| 地名 `taiwan_place_names.json` | osmtoday.com 檔，OSM 到 **2026-10-18**，2026-10-22 產出：聚落 16,626、村里 7,779、鄉鎮市區 367 | OSM，ODbL | 地名變動緩慢 | 不急。 |
| 地點、水域、不可建地、高程 `taiwan_places.json`、`taiwan_water.json`、`taiwan_no_build.json`、`taiwan_heights.dat` | osmtoday.com 2026-10-06 整包檔（2026-10-09、10 產出） | OSM ODbL | 緩慢 | 不急。 |
| 建物蓋度 `taiwan_coverage.dat`、建物圖塊 `taiwan_buildings.pmtiles` | **Overture `2026-09-23.1`**（2026-10-10 產出）；高度補 GHS-BUILT-H R2023A | Overture Maps Foundation，ODbL；內政部 113、114 年統計 | Overture 約每月出新版，現在已有 2026-10 的版本（**待查**），新版建物多一個月 | 不急；若要換要重跑整個圖塊流程。 |
| 底圖 `BaseMap/taiwan.pmtiles`、地形 `taiwan_terrain.pmtiles` | OSM 2026-10-24 檔（OSM 到 2026-10-21），道路 `oneway` 2026-10-29 加 | OSM ODbL、OpenFreeMap 字型（OFL） | 緩慢 | 不急。 |
| 寺廟 `BaseMap/taiwan_temples.json` | 2026-10-22 產出，19,201 間 | 作者 geo-scene 參考庫（內政部、文化部；政府開放授權） | 緩慢 | 不更新。 |
| 車站周邊地標 `taiwan_station_landmarks.json` | **2026-11-03** 下載的 osmtoday 檔，地標 1,717、路口 10,591 | OSM ODbL | 最新 | 不更新。 |
| 公車（`real-buses`） | **TDX 2026-10-25** 抓（`tdx-check.yml` 的 6 次 run） | TDX | 公車路線每月都在變 | 不急。 |
| 台鐵誤點分析 `tra-delay-analysis` | TDX 歷史誤點 2025-11-20 到 2026-10-26，24,390,062 筆 | TDX | 每天多一天 | 若要更新分析報告才重抓。 |
| 觀光景點 `tools/tourism-spots`、機廠 `rail-depots`、各 kit 的建模 | 景點檔沒標抓取日；機廠是 2026-10-29、11-01、11-05 的 OSM 整包檔 | 手工整理與 OSM | — | 不急。 |
| 票價 | 台鐵票價 2025-06-23 起平均調漲約 26.8%（報導）；遊戲裡高鐵每公里票價依 NTD1 決策維持舊水準乘 3（NT$1.35），官方票價表只作示範；其餘走遊戲自己的經濟 | 遊戲自訂 | 高鐵票價 20 年沒調，新車 2027-07 後才檢討 | 不更新（遊戲平衡不跟票價走）。 |
| 國定假日、農曆 `holiday-calendar` | 工具產出（農曆日期表） | 公開曆法 | 每年行政院公布隔年辦公日曆表（約 6 月） | **2027 年的辦公日曆公布後要補**（查 `holiday-calendar` 目前涵蓋到哪一年；這份沒有讀）。 |

### 訂閱結束前值得重抓（作者說這個月訂閱完就取消）

這裡的「重抓」指**會因為訂閱結束而變難**的那一類（要跑雲端 session 下載大檔、重產大圖塊的），不是所有。依價值排序：

1. **台鐵時刻表與台南段**。理由：台南地下化第一階段 10 月中通車，台鐵時刻表與台南段的軌道、車站可能已經變了；打包的時刻表是 2026-10-16 抓的，剛好在通車前後。做法：重抓 ods.railway.gov.tw 的 14 天時刻表（`extract_tra_schedule.py`），OSM 台南一帶的 `railway=*`（整包檔 osmtoday 的 `asia/taiwan.pbf`，**CLAUDE.md 寫雲端環境下載得到**）。要重產 `tra-schedule.json`、`tra_station_info.json`，並看 golden／fixture 有沒有被動到（Linux 驗）。
2. **TDX 快照整批**（誤點、公車、車站出口）。理由：TDX 資料是用 `tdx-check.yml` 抓的（需要作者的 TDX 金鑰，我沒查金鑰存在哪裡）；若抓取靠 Claude session 或訂閱才能跑，訂閱結束後就沒人重抓。這些資料有「過期」的問題但沒有「消失」的問題，只在作者想要新一批時才有急迫性。
3. **OSM 整包檔**（地名、地點、底圖、車站地標）。理由：最新是 2026-11-03，都不舊；**不急**，除非作者想在訂閱結束前把 11 月的 OSM 一次吃下。
4. **Overture 建物**（`2026-09-23.1`，約 196 萬棟、重產要幾小時）。理由：已有新版但沒有玩家看得出的變化；**不建議**。

### 還沒有、但值得先記下來的後續（待查）

- **桃園捷運綠線北段**（預計 2026 年底，G11—G15b 共 7 站）：通車後遊戲裡的桃園系統要不要加，要新的 TDX 資料。
- **高鐵新世代班表**（2027 年初）與 **N700ST 新車**（2027-07 起）：時刻表與車輛都要更新。
- **台南地下化後續**：林森站（2029）、南台南站（2030）、整體 2031 年 3 月。

## 本次沒做、留給下一個 session

- 沒讀官方公告原文：台鐵改點、台南通車實際日期、桃園綠線日期都是新聞。
- 沒查：`pull_request_target` 在本倉庫的使用、macOS 上 SwiftUI 檔的完整編譯警告、MapLibre 7.0.0 的 `maplibre-native` 完整發佈說明。
- 沒查 `holiday-calendar` 涵蓋到哪一年、`tourism-spots` 的抓取日。
