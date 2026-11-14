# 玩家開航空航線：前置研究（2026-11-14）

作者 2026-11-14 在專案對話要「追加航線功能的前置作業」，附了一份在別處查到的資料（資料來源、授權、GitHub 專案、分階段建議），並補充「我很久以前 Ci 裡面也有自己開發一套」。這份文件把那份資料逐項向官方來源核實，對照遊戲現在已有的機場系統與作者舊版的航空系統，提出分階段計畫。**只是研究，沒有改任何程式、存檔或 golden。**

## 0. 結論（先講）

1. **不必從零做，遊戲已經有一半。** 現在的 main 已有：GameCore 的真實機場（`Airport`，決策 695；全台 13 座、香港另讀）、每座機場的航點與一年旅客（`AirDestination`，決策 700）、每小時的起降架次（`AirportDay.landings`／`takeOffs`）、航空旅客轉乘到玩家鐵路（`TouristFlows`）、OSM 鋪的 3D 跑道滑行道機位（決策 699、733）、照架次起降滑行的 3D 飛機與「跟著飛機看」（決策 699、702）、2D／3D 機場標記、開航解鎖香港（決策 712）。缺的只有**「玩家自己的航線」**：選兩座機場、排班、飛機照班表飛、載客收錢。
2. **作者舊版（`Ci/`）有一整套玩家經營的航空系統**，是作者自己的作品，可以直接移植：週班表（星期幾＋當地分鐘＋時區）、飛機輪轉（同一架飛機接下一段，過站 45 分）、旅客群組與多段行程（最多 3 段、轉機 90 分到 24 小時、繞路 1.6 倍內、超賣 2%）、星期與每小時的需求權重、設施（跑道、機位、安檢、人力）過載就取消或誤機、約 190 型飛機的座位、航程與收益／利潤曲線。**舊版的航線市場與機場清單是從伺服器 API 拿的，快照裡沒有那份資料**；設施容量的常數所在的 `aviation_economy_rules` 也不在快照裡。這兩樣是缺口。
3. **第一個里程碑（在地圖上選兩座真實機場、建一條航線、飛機照時刻表飛、和鐵路產生轉乘）可以照渡輪（決策 585）的做法做**：GameCore 多一個 `AirRoute`（兩座 `Airport`、機型等級、班表 `BusService`、架數），旅客照日計畫算（不逐 tick 模擬飛行），搭機旅客照**玩家航班的時刻**進既有的 `TouristFlows`，轉乘需求自然出現。3D 飛機是畫面層照班表插值，不進 GameCore。**要升存檔版本一次**；golden、replay 不動（沒有航線的世界一個值都不變）。估計 GameCore 約 700–1,000 行加測試、App 約 1,000 行，分 3 個 PR。
4. **資料：初版不需要任何付費 API 或即時資料。** 機場與跑道用遊戲已有的 OSM 工具，國內航點與旅客用民航局統計（決策 700 已用），全球機場座標用 OurAirports（公有領域，可直接內建）。真實的國內線班表可以用 **TDX 的航空定期班表**（政府資料開放授權，透過既有的 `tdx-check.yml` 抓），但內容還沒抓過、沒驗證。
5. **作者貼的資料大致對，但有四處要改**（細節在第 1 節）：
   - BlueSky 現在是 **MIT**（作者的資料寫 MIT，正確）；OpenAP 是 **LGPL-3.0**（正確，照規則只讀想法、不抄）。
   - OpenSky 比資料講的更嚴：**只准非營利研究與教育，營利用途要書面授權，而且不准轉給別人**。連「研究飛行行為」也不在遊戲開發能用的範圍裡，建議完全不用。
   - 臺灣 eAIP 本身沒有寫重製條件；民航局主網站的「政府網站資料開放宣告」採政府資料開放授權條款第 1 版，eAIP 在民航局的子網站，**推論**同樣適用但沒有明文。而且 eAIP 的程序圖對遊戲用處很小。
   - OpenFlights：資料是 ODbL（附 DbCL），程式是 AGPL-3.0，航線資料的來源 2014 年 6 月就停止更新，官方頁面自己寫「只有歷史價值」。**不建議用**：遊戲要的國內與香港航點已經有更新、授權更單純的官方統計。
6. **方向上的提醒**：決策 695 第 10 節寫「玩家經營航空公司（買飛機、排航線）：作者 11-04 說了不是這個」。這次作者主動要研究追加航線，這份文件把它當成新的方向；真的開工時要寫一個新決策，明說取代 11-04 那句話的哪一部分。

## 1. 資料來源與授權（已核實）

程式碼授權與資料授權分開看。「核實」欄寫我實際看了什麼；沒看到的寫 UNVERIFIED。

### 1.1 資料

| 來源 | 內容 | 資料授權 | 核實 | 對遊戲的用途與建議 |
| --- | --- | --- | --- | --- |
| **OurAirports**（`davidmegginson/ourairports-data`） | 全球 86,363 個地點；有定期航班且有 IATA 代碼的 4,132 座；跑道、導航台、頻率 | **公有領域**（Unlicense 的「free and unencumbered … released into the public domain」） | 2026-11-14 clone 了 repo 讀 `LICENSE`；`ourairports.com/data/` 的 TLS 憑證過期，官方頁面沒讀到 | **建議用**：海外航點的座標（大圓距離）、OSM 沒畫好的跑道頭（例如赤鱲角 07C/25C 被 OSM 標成 displaced_threshold，決策 733）。只取欄位，不必署名（但資料來源頁可以列）。台灣 13 座都在（TPE、TSA、KHH、RMQ、TNN、CYI、HUN、TTT、MZG、KNH、LZN、MFK、KYD） |
| **OpenStreetMap** | 跑道、滑行道、停機坪、機位、空橋、塔台、航廈 | **ODbL 1.0** | 讀了 OSMF 的 Attribution Guidelines（2026-09-10 版），有「Computer games and simulations」一節：署名可以放在啟動畫面、遊戲畫面、遊戲中、credits 頁、選單或其他適當位置；第一處沒有細節時要在適當位置給完整說明；只在用到 OSM 的區域或圖徵署名即可 | **已在用**（決策 385、699、733，`tools/airfields/build_airfields.py`，`DataSourceCredits`）。航線功能不必多加 OSM 資料 |
| **OpenFlights**（`jpatokal/openflights`） | 67,663 條航線、3,321 座機場、548 家航空公司（2014 年 6 月）；機型 | 資料 **ODbL 1.0 ＋ DbCL 1.0**；另有商用授權（簡單用途一次 100 美元起） | clone 了 repo 讀 `data.php`（官網資料頁的原始碼）：「The third-party that OpenFlights uses for route data ceased providing updates in June 2014. The current data is of historical value only.」；`routes.dat` 確實 67,663 行；程式是 **AGPL-3.0**（`LICENSE`） | **不建議用**。航線過時 12 年；ODbL 要求衍生資料庫公開時同樣授權。遊戲需要的國內與香港航點已由民航局統計提供（決策 700） |
| **民航局統計**（民航運輸統計、年報） | 各機場每年旅客、架次、航點 | 民航局網站「政府網站資料開放宣告」：**政府資料開放授權條款第 1 版**，可重製、改作、商用，要註明出處；機關特別聲明須同意的影音圖像除外 | 讀了 `www.caa.gov.tw/article.aspx?a=1433`（最後更新 2023-09-14） | **已在用**（決策 695、700）。航線的旅客量照這份 |
| **臺灣 eAIP**（`ais.caa.gov.tw/eaip/`） | 機場圖、儀器程序、航路 | eAIP 本身**沒有**著作權或重製聲明（讀了 2026-10-29 生效的 AMDT 05/26 的封面與 GEN 0.1）；**推論**：它是民航局的子網站，上一列的開放宣告應該也涵蓋，但沒有明文 | GEN 0.1 只寫出版機關、ICAO 依據與勘誤聯絡；還寫「第三方提供的飛航資料要以民航局發布的為準」 | **不急**。遊戲不模擬儀器程序；跑道與機位 OSM 已有。若要用，先寫信問民航局飛航服務組 |
| **TDX 航空**（`/api/basic/v2/Air/...`） | 國內與國際定期班表（`GeneralSchedule/Domestic`、`International`）、機場、航空公司、即時起降（FIDS） | **政府資料開放授權條款第 1 版**（照參考庫 `tdx-snapshot-2026-10/DATA_USE_NOTICES.json` 的 TDX 慣例；航空這幾個 API 的條款**沒有逐一核對**） | 2026-11-14 不帶金鑰呼叫四個路徑都回 401「Valid API Key Required」（路徑存在，不是 404）；內容沒看到 | **建議下一步抓**：用作者既有的 `tdx-check.yml`（金鑰留在 GitHub）抓一次國內班表，放進參考庫，當「照真實航線」的預設班表與每小時形狀。點數消耗未知 |
| **FAA d-TPP** | 美國機場圖與程序 PDF | **推論**：美國聯邦政府作品依 17 U.S.C. §105 不受著作權保護；FAA 頁面上沒看到明文 | 讀了 FAA d-TPP 頁面，沒有授權段落 | **不用**：遊戲沒有美國地圖 |
| **OpenSky Network** | 真實飛機位置、歷史軌跡 | **只准非營利研究與教育**；營利或商業單位任何用途都要書面授權；REST API 用在任何上線產品要書面授權；**不得轉給他人** | 讀了 `opensky-network.org/about/terms-of-use/` 全文 | **不用**。作者貼的資料寫「研究飛行行為，不建議直接依賴正式產品」：其實連研究用途都要是非營利研究機構 |
| **Aviationstack** | 航班與航線 API（付費） | 網站條款：不得修改、複製、散布、建立衍生作品 | 讀了 `aviationstack.com/terms` | **不用**：內建進 App 等於轉發 |
| **AeroDataBox** | 未來航班、機場進離場（付費） | 只能用付費管道取得的內容商用；快取最多 7 天（或 Cache-Control 指定的秒數），不得再授權 | 讀了 `aerodatabox.com/terms/` 第 3、5.3、5.5 條 | **不用**：離線內建違反 7 天上限 |
| 參考庫 `geo-scene-reference-clean` 的歷史航跡 | 台灣 17 場、日本 78 場的航跡 GeoJSON | 文件寫「沒有 DB 或 FR24 fallback」，原始資料來源**沒查清楚** | 讀了 `source/docs/features/historical-flight-trails/README.md` | **先不用**，等查清楚來源與授權 |

### 1.2 程式（GitHub 專案）

2026-11-14 把每個 repo clone 到暫存區，讀它自己的 `LICENSE`。

| 專案 | 程式授權（實際讀到的） | 最近一次 commit | 和遊戲的關係 | 建議 |
| --- | --- | --- | --- | --- |
| `ghtomcat/opensim` | **MIT**（© 2026 Markus Leutwyler） | 2026-11-10 | 瀏覽器飛行模擬器。跑道取 OurAirports，滑行道、機位、航廈取 OSM（Overpass），SID/STAR 取 FAA CIFP 與 **X-Plane 導航資料**（後者的授權沒查，不用） | 遊戲已有同樣的 OSM 機場工具（決策 699，讀整包 pbf、不用 Overpass）。可借：`scripts/build-runways.py` 從 OurAirports 補跑道頭的作法；`core/taxi-graph.js` 只 182 行，遊戲的滑行路網已有 |
| `ATMRI-NTU/OpenTaxi` | **MIT** | 2026-06-01 | 地面滑行調度、多架衝突 | 遊戲的 3D 滑行只是畫面，同跑道起降隔 75 秒就夠（決策 699）。第五階段（地面調度變成玩法）才讀 |
| `TUDelft-CNS-ATM/bluesky` | **MIT**（© 2025 TU Delft） | 2026-10-12 | 空中交通模擬：性能、航路、間隔、衝突 | 遊戲不模擬空中衝突。性能資料若要用，先查它內含資料的授權 |
| `TUDelft-CNS-ATM/openap` | **LGPL-3.0** | 2026-06-18 | 飛機性能、油耗、排放 | 照 CLAUDE.md：copyleft 只讀想法，不抄程式；**油耗與成本改用作者舊版自己的曲線**（第 2 節） |
| `gboeing/osmnx` | **MIT** | 2026-11-07 | Python 抓 OSM 圖徵與路網 | 不需要：遊戲已用 pyosmium 讀整包（決策 93），加依賴要作者同意 |
| `mapbox/turf-swift` | **ISC** | 2026-10-13 | Swift 的地理運算 | 不需要：大圓距離與插值各十幾行，GameCore 不能 import Foundation，自己寫比較單純；不加依賴 |
| `jpatokal/openflights` | **AGPL-3.0**（程式） | 2026-11-09（`routes.dat` 最後一次資料更新 2014-08-06，之後 2017-02-02 只重匯出） | | 程式不抄（AGPL）；資料見上表 |
| RoutePilot | 沒有 clone（作者的資料沒給 repo 路徑） | | | UNVERIFIED，不用 |

## 2. 作者舊版的航空系統（`Ci/reference_snapshot/lib/aviation_*`）

這是作者自己做的網頁交通經營遊戲的航空模組（`docs/WEB_REFERENCE_STUDY.md` 已研究過一部分）。檔案是壓縮過的 JavaScript，2026-11-14 用 prettier 展開後讀。總共約 6 萬行，其中 4 萬行是 UI（`flight_planner_panel`、`flight_info_panel`、`flight_layer`）。

| 舊版檔案（行數，展開後） | 做什麼 | 目標（遊戲裡要接到哪） | 要不要搬 |
| --- | --- | --- | --- |
| `aviation_timetable`（690） | 週班表：每班有 `dep`／`arr`、星期幾 `days`、當地分鐘 `minute`、機場時區；同一 `pair_group_id` 的幾段接成一架飛機的輪轉；用小根堆找下一班出發 | GameCore `AirRoute` 的班表（第 4 節）。台灣國內線不跨時區，**第一階段用既有的 `BusService.runs`（一天的出發分鐘）就夠**；時區與星期班表留到國際線 | 第一階段搬規則（輪轉、過站），不搬時區 |
| `aviation_operations`（5,289） | 引擎核心。常數 `de`：`maxLegs 3`、`detour 1.6`、`minConnection 5400`（90 分）、`maxConnection 24 h`、`oversell 0.02`、`dailyExitMax 0.05`、`weekWeights [1.05,1,1,1,1.15,0.9,0.9]`、24 個 `hourWeights`；過站 2,700 秒（45 分，`isThrough`）；設施負載 `load = 架次或旅客 ÷ (設施數 × 容量)`，跑道或機位超過 1 就照超出的比例取消（`cancelRate`），安檢或人力超過 1 就照比例誤機（`missRate`），90% 與 100% 發通知 | 過站 45 分已用在 3D（決策 699）。需求權重 → `AirRoute` 的旅客時段；設施負載 → 第三階段的機場容量 | 第一階段：過站、星期權重。第三階段：設施負載（**容量常數 `AviationEconomyRules.capacity` 不在快照裡，缺口**） |
| `aviation_demand_plans`（916） | 每個 OD 一週的總量，乘星期 × 小時權重做成每分鐘的累積曲線（`minute-cdf-v1`），每次放出「累積 − 已放」，小數留著存檔 | 遊戲的 `TouristFlows` 已經是同樣的「每小時、整數分配」作法（決策 174、533），不必再搬 | 想法已在，不搬程式 |
| `aviation_waiting_queue`（766）、`aviation_passenger_store`（267） | 每個 OD 先進先出的旅客群組，同一小時併成一組；欄位陣列存 | 鐵路的旅客系統已有候車與上車；航空段第一階段照渡輪「一天最多載多少」的日總量，不逐人 | 不搬（第三階段若要逐班超賣、誤點再看） |
| `aviation_economy_curve_data`（576）、`aviation_economy_curves`（160）、`aviation_economy_completed_data`（319） | 74 型飛機的座位、航程（km）與收益／利潤三次多項式（以海里為變數，`scale 0.584`，各型平移），航程 80% 以後的尾段處理；另 115 型「補齊」規格（參照某一型，毛利差 `marginDelta`） | GameCore 的機型等級表（第 4 節）：每級的座位、航程、每公里成本、每座公里收益 | **搬數值**。遊戲照決策 698、701「不寫廠牌與型號」，所以把舊版的型號歸到遊戲的四級（十九座、七十座、窄體、廣體），每級取代表型號的曲線，換成定點整數（例如每千座公里的元） |
| `aviation_disruptions`（869） | 天候關閉 2–4 座機場 6–24 小時、油價、節慶 | 遊戲用自己的颱風關機場（決策 695） | 已有，不搬 |
| `aviation_events_ui`、`airport_pa`、`audio/airport-pa/` | 事件卡、機場廣播與環境音 | 音樂那條線（機場廣播是作者的素材） | 第四階段，給音效 session |
| `flight_layer`（9,427）、`flight_planner_panel`（22,187）、`flight_info_panel`（10,953）、`app-feature-flight.css` | 地圖上的航線弧線、飛機、排班面板、航班資訊卡 | 版型借法已定（ARCHITECTURE 2026-10-14：航班卡 → 列車卡 A、機場出發表 → 即將進站看板 B、飛機運行甘特圖 → 列車運用表 A）。航線面板照纜車／渡輪卡的樣子 | 借版型與流程，外觀照遊戲畫風重畫（同 2026-10-14 的定案） |
| `flight_history_client`（2,120） | 從 `/api/flight-history/*`、`/api/aviation/route-options`、`/api/aviation/active-market` 抓機場清單、航線選項與市場 | | **缺口：伺服器資料不在快照裡**。改用民航局統計與 TDX |
| `flight_history_pack_codec`（232） | 航跡打包編碼 | | 不需要 |

缺口小結（參考庫沒有、要自己做或另找資料）：航線市場（每對機場一週多少人）、設施容量常數、經濟規則檔 `aviation_economy_rules`、真實班表。

## 3. 對照現有架構：要接到哪些型別與系統

| 系統 | 現在有什麼 | 航線要接的地方 | 動 GameCore／存檔？ |
| --- | --- | --- | --- |
| 機場 | `Airport`（`Sources/GameCore/Passenger/Airport.swift`）：航廈 `PlanPoint`、平均一天旅客與架次、開放時段、`destinations: [AirDestination]`；`GameWorld.airports`（最多 16 座）；`AirportCatalog` 照地圖範圍補 | `AirRoute` 用兩個 `Airport.id`；兩座都要在同一張地圖（全台灣地圖 13 座都在） | 讀，不改型別 |
| 航點與旅客量 | `AirDestination` 的一年旅客與架次；`AirportDay.departures` 照航點分當天的班數與旅客 | 玩家航線分走「這兩座機場之間」那個航點的一份旅客；分到多少照座位與班次 | 改 `airportDays()` 的分配（玩家航線的份從自動航班扣） |
| 時刻表與 tick | 鐵路有逐分鐘的時刻表；公車、渡輪、纜車用 `BusService`（`.every(minutes:)` 或 `.runs([分鐘])`）與日容量；機場是每天中午算一次計畫、午夜記一次 | `AirRoute.service: BusService`；**不逐 tick 模擬飛行**：起飛與降落的分鐘從班表與航程算，日計畫算一次 | 新增 |
| 車站與轉乘需求 | 機場站：航廈 800 m 內最近有停車的站；搭機旅客照班機時段進 `TouristFlows`（`passengerExtraFlows`）、上車付票價 | 玩家航班的旅客照**玩家班表的時刻**（國內線起飛前 1 小時到、降落同一小時離開，決策 700）進同一條管道 | 改 `Airport.swift` 的時段形狀：自動航班照 `flightShape`，玩家航班照它的班表 |
| 錢 | 渡輪：`FerryDay`（乘客、票收、成本、停航）、`spendOnFerries`、`settleFerries` | `AirRouteDay`；買飛機的錢、每天的營運成本、票收；票價照舊版曲線換算 | 新增帳列（「航空」） |
| 颱風 | 颱風蓋到航廈整天關閉 | 兩端任一關閉，那條航線那天停航（和渡輪一樣照付成本） | 沿用 |
| 2D 地圖 | 機場膠囊（決策 699）；渡輪是碼頭間直線虛線 | 航線是兩座機場間的大圓弧（2D 是平面，台灣尺度近似直線即可）；飛機記號照時間插值 | App 端 |
| 3D 地圖 | `Map3DAircraft`：照 `airportDays()` 每小時的架次排班，7 km 外出現、3° 下滑、滑行到機位、停 45 分、後推、起飛 9° 爬升，沒有亂數 | 多一個來源：玩家航班在**它的出發／抵達分鐘**起降；中途不畫（3D 只看得到鏡頭附近） | GamePresentation，不動 GameCore |
| 圖鑑與跟隨 | 圖鑑飛機頁、`FollowAircraft` | 跟隨列多「這是你的航班」與航線名 | App 端 |
| 存檔 | 現在 `SavedGame.currentVersion = 101`；世界的 `"airports"` 欄位（v90） | 世界多 `"airRoutes"`（空的不寫）；升版本一次（取 #2118 最新的下一號），加 `SaveFixtures/v<N>-air-routes.json` | **升一次** |
| golden／replay | | 沒有航線的世界每個值都不變（同決策 695 的做法：空的時候每個新分支第一行就回去） | 不動 |
| 記憶體 | 手機 3D 峰值約 2,445–2,472 MB（決策 749 末節）；飛機與地勤車模型已在模型包（12 個模型、54,240 頂點、每份 2.2 MB，決策 699） | 不加新模型；玩家航班只是多幾個實例；2D 弧線幾十個點 | 預估增加 < 1 MB（推論，沒量） |
| Linux 測試 | GameCore 不 import Foundation；`AirportTests`、`AirportReportTests` | 大圓距離用整數或 `Double` 的自寫函式（GameCore 已有自己的三角函式？**沒查**，要在實作 PR 確認）；新測試 `AirRouteTests` 手算 | 新增 |

## 4. 分階段計畫

每一項照 NEXT_PRIORITIES §19 的權重（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）打分。

### 階段 0：資料準備（不動 GameCore，0.5 天）

- TDX 抓一次國內線定期班表（`tdx-check.yml`，作者的金鑰留在 GitHub），放進參考庫 `Railway/tdx-snapshot-2026-10/` 或新資料夾，附 `DATA_USE_NOTICES.json`。看它有沒有每班的時刻、星期、機型、航空公司。
- OurAirports 的 `airports.csv`、`runways.csv` 只留需要的欄位（第 5 節）。
- 分數：玩家 2、開發 4、美術 1、鐵道迷 4、音樂 1 → **2.45**（是 M1 的前提，跟 M1 一起排）。

### 階段 1（第一個里程碑 M1）：選兩座機場、開一條航線、飛機照班表飛、和鐵路轉乘

- **GameCore**（PR 1，升存檔）：
  - `AirRoute`：`id`、兩個 `Airport.id`、機型等級（四級之一）、`service: BusService`、架數；`legMetres` 照兩座航廈的大圓距離（GameCore 的 `PlanPoint` 是平面座標；全台灣地圖的尺度用平面距離也可以，誤差要量）。
  - 指令：`createAirRoute`、`setAirRouteRuns`、`setAirRouteAircraft`、`removeAirRoute`，失敗不留半套（failure atomicity）。檢查：兩座機場不同、在開放時段內起降、架數夠飛（來回時間 = 2 × (航程時間 + 過站 45 分)，舊版的 2,700 秒）。
  - 航程時間：機型等級的巡航速度加起降與滑行的固定分鐘。**數值來源要定**：舊版沒有直接的「航程 → 時間」表（`duration_min` 是伺服器給的），要從 TDX 真實班表的表定時間回推，沒有 TDX 就是本專案自己定（寫進決策）。
  - 旅客：兩座機場之間那個航點一年的旅客 ÷ 365 × 星期權重（沿用 `AirportRules.dayFactor`），玩家分到的份 = 玩家座位 ÷（玩家座位 ＋ 自動航班的座位），上限是日座位數。兩座機場之間沒有航點的組合（例如松山↔高雄，現實沒有定期航班）一開始是 0 人：**這是規則上的選擇，要在決策裡定**（照實沒人，或照兩地人口與距離給一個小的量）。
  - 轉乘：玩家航班的旅客照它的出發／抵達時刻進 `TouristFlows`，所以兩端的機場站會多出「趕某班飛機」的人。
  - 錢：買飛機、每天成本、票收（機型等級的曲線取自舊版，換成定點整數）。
  - 估計：GameCore 約 700–1,000 行、測試約 500 行；新 fixture 一個；決策一個。
- **App（PR 2）**：建設多一個「航線」模式（照渡輪模式：點兩座機場的膠囊、選機型與班表、預覽價錢與座位）；航線卡（照渡輪卡）；2D 地圖畫航線與飛機記號。估計約 800–1,000 行，GamePresentation 加 Linux 測試。屬「新畫面」，合併前給遊戲規劃看截圖（決策 482 的修正）。
- **3D（PR 3，Mac）**：`Map3DAircraft` 多讀玩家航班的時刻；跟隨列寫航線名。屬大型 3D 視覺改動，合併前給作者看截圖。估計約 200–300 行。
- 分數：玩家 4、開發 3、美術 3、鐵道迷 4、音樂 2 → **3.30**（和 §25 的國際機場 3.25 同一級）。

### 階段 2：真實航線與班表

- 「照真實航線開」的預設（同渡輪的「照真實航線拉淡水—八里」）：TDX 班表裡有的國內線（松山↔澎湖、金門…；**金門、馬祖不在台灣地圖範圍**，只能當航點），預設班次與時刻照真實。
- 自動航班的每小時形狀改用真實班表（取代 `flightShape` 這個本專案自己定的形狀，決策 695 第 6 節標了 UNVERIFIED）。這會改機場的數字，**動 golden 的可能性要先查**。
- 規模：GameCore 約 300 行；資料檔幾十 KB。分數：玩家 3、開發 3、美術 1、鐵道迷 5、音樂 1 → **2.70**。

### 階段 3：經營深度

- 機場容量：跑道、機位過載就取消（舊版的 `cancelRate`、`missRate`；容量常數是缺口，要自己定或從 OSM 的機位數推）。
- 多段行程與轉機（舊版 `maxLegs 3`、轉機 90 分）、超賣 2%、誤點。
- 機型逐型（不只四級）要先和決策 698、701「不寫廠牌與型號」對齊。
- 規模：GameCore 約 1,000 行以上，可能升存檔。分數：玩家 3、開發 2、美術 1、鐵道迷 3、音樂 1 → **2.15**。

### 階段 4：國際線與海外地圖

- 時區與星期班表（舊版 `aviation_timetable` 的作法）；海外端是航點（`AirDestination`），不在地圖上；香港地圖（決策 712）已能開。
- OurAirports 的全球座標算距離。分數：玩家 3、開發 2、美術 2、鐵道迷 3、音樂 1 → **2.30**。

### 階段 5：聲音與機場細節

- 機場廣播與環境音（舊版 `audio/airport-pa/`，作者的素材）；地面調度（OpenTaxi 的想法）。分數：玩家 2、開發 2、美術 3、鐵道迷 2、音樂 5 → **2.65**。

順序建議：階段 0 → 1 → 2 → 5 → 4 → 3。階段 1 和 2 要動 GameCore，照規則同時最多兩張。

## 5. 離線資料管線

都在 Mac 或雲端 Linux 上先處理，App 只讀整理好的小檔，不連任何航空 API。

| 步驟 | 輸入 | 工具 | 輸出（App 內建） | 大小 |
| --- | --- | --- | --- | --- |
| 機場場面 | osmtoday `asia/taiwan.pbf`、`hong_kong.pbf` | 既有 `tools/airfields/build_airfields.py` | 既有 `taiwan_airfields.json`、香港包的 `airfields.json` | 已有（台灣約 98 KB） |
| 跑道頭補正 | OurAirports `runways.csv`（約 4 MB） | 新的小工具：只取 OSM 跑道缺端點或被標成 displaced_threshold 的那幾條 | 併進上面的 json | 幾 KB |
| 全球航點座標（階段 4） | OurAirports `airports.csv`（12.7 MB） | 篩 `scheduled_service=yes` 且有 IATA：4,132 座，只留 IATA、ICAO、名稱、緯經度（4 位小數）、國家 | `air_destinations.json` | 實測約 268 KB，gzip 約 106 KB；只留遊戲航點會用到的會更小 |
| 航點旅客 | 民航局年報 | 既有（決策 700 寫在 GameCore 的目錄） | 既有 | 已有 |
| 真實班表（階段 2） | TDX `Air/GeneralSchedule/Domestic`（與國際） | 新工具：照機場對整理成「每天哪幾分鐘、星期幾」，丟掉航空公司名稱與班號（遊戲畫面不寫航空公司，決策 698、701） | `air_timetables.json` | **推論**：國內線一天約數百班，幾十 KB；沒抓過 |
| 機型等級數值 | 舊版 `aviation_economy_curve_data` | 一次性換算腳本：四級各取代表型號，輸出定點整數 | 寫進 GameCore 的常數（不是資料檔） | 0 |

格式照遊戲現有的資料檔：JSON、座標用 1e-6 度整數（`taiwan_airfields.json` 的慣例）、每份附 `source` 與日期。資料來源頁（`DataSourceCredits`）加 OurAirports（公有領域，可不列但建議列）與 TDX 航空。**不打包 OpenFlights、OpenSky、Aviationstack、AeroDataBox 的任何資料。**

## 6. 五個角度（這份研究的建議）

- 玩家：先給「把線拉到機場、再開一條自己的航線把人送到離島」這個新玩法，不用學整套航空公司經營。
- 鐵道迷：機場、航點、旅客都已是真實數字；班表可以接 TDX 的真實國內線；不畫航空公司。
- 開發：照渡輪的形狀加一個型別，日計畫一次、不逐 tick；舊版有現成的過站、權重與機型曲線可搬。
- 美術：不需要新模型，四級飛機與地勤車都在；新的只有航線模式的版面與 2D 弧線。
- 音樂：第一階段無；舊版的機場廣播留給階段 5。

## 7. 哪些是推論、哪些沒驗證

**推論**
- 臺灣 eAIP 適用民航局的開放宣告（eAIP 子站沒有明文）。
- FAA 資料屬美國政府作品、不受著作權（頁面上沒有看到明文）。
- TDX 航空 API 的授權與其他 TDX 資料一樣是政府資料開放授權第 1 版；國內班表大小幾十 KB。
- 航線功能對記憶體增加 < 1 MB；全台灣地圖用平面距離代替大圓距離的誤差可以接受。
- 各階段的行數與分數是估計。

**沒驗證**
- OurAirports 官方資料頁（`ourairports.com/data/`）：TLS 憑證過期，沒讀到；授權是從 GitHub repo 的 `LICENSE` 讀的。
- TDX 航空班表的實際內容、欄位、點數消耗（沒有金鑰，只確認路徑存在）。
- RoutePilot 的 repo 與授權。
- opensim 內含的 X-Plane 導航資料的授權；BlueSky 內含性能資料的授權。
- 參考庫 geo-scene 歷史航跡的原始資料來源。
- 舊版的需求數值（`hourWeights` 等）用在台灣國內線合不合理：沒有和真實班表比對。
- GameCore 是否已有可用的三角函式（大圓距離要用）：沒查。
- 沒有任何程式在模擬器或裝置上跑過：這份是文件，App 與 GameCore 都沒改。
