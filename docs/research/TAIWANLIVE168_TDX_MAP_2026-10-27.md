# 生活168 → 官方來源（TDX／縣市開放資料）對照（2026-10-27，派工單 AG）

作者 2026-10-27：「這網站很多資料都是 Tdx 來的 可以先參閱 再去用 api 查詢嗎」。遊戲規劃 session_01YGNNunheBBBwyekk4Pq7b4 開的派工單；執行 session_01YGNNuouN9pCXp1EYMxrVzw。

**生活168（https://www.taiwanlive168.com）只當指路牌**：它是第三方網站，不是作者的。它的資料、文字、程式不抄、不爬。這份只讀了它首頁列出的工具清單（`/tools/bus`、`/tools/tra`、`/tools/thsr`、`/tools/metro`、`/tools/youbike`、`/tools/traffic`、`/tools/garbage-truck`、`/tools/invoice`、`/tools/lottery`、`/tools/air-quality`，另有指南文章 `/blog/realtime-parking-space-guide`），每一類再到官方來源自己查。各工具頁與指南文章沒有逐頁讀（UNVERIFIED：它說的來源只有公車工具寫「交通部 TDX」，垃圾車寫「各縣市環保局」，發票寫「財政部」，樂透寫「台灣彩券」，其他頁沒寫）。

**抓下來的資料**在私庫 `Railway/tdx-live-2026-10/`（a91453/railway-reference-private#108，draft，8.5 MB／100 MB；`00_READ_ME_FIRST.md`、`DATA_USE_NOTICES.json`、`python3 -I tools/verify.py` 過）。遊戲 repository 不放資料、不改 Sources/，GameCore、存檔、golden、replay 都不動。

## 1. 重點

1. **市區公車的路線形狀、站牌、班距，遊戲早就有了**（決策 400 的 10i-3：`RailwayGameApp/Resources/RealBuses/` 22 個縣市，臺北、屏東是 TDX 直接抓）。「公車班次一直在等 TDX」的缺口是**實際班次**：`Bus/Schedule/City/Taipei` 的 591 個子路線裡 538 個有 `Timetables`，共 **35,493 班**；**每班只有起站一個發車時間**（`StopTimes` 長度全是 1），沒有每站時間。另 141 個有 `Frequencys`（時段＋最短／最長班距＋星期），88 個兩者都有。派工單 AB（決策 438，獨立市區公車）要的班次可以由此來，每站的到站時間要自己用路線長度與速度推。
2. **公車票價有官方表**：`Bus/RouteFare` 臺北 722 筆（階段票，一段 15 元、優待 8 元；`FarePricingType` 0），高雄 303 筆（起迄站票價，`FarePricingType` 1，原始 36 MB）。CITY_BUS_ROADS_DESIGN 用的「一段 NT$15＝$5」可以由此驗證，不必再靠新聞。
3. **捷運班距：只有 5 個系統**。`Rail/Metro/Frequency/<系統>` 被 TDX 明說只收 `TRTC, KRTC, TYMC, TMRT, NTMC`（run 179 對 `KLRT` 回 HTTP 400）。高雄輕軌、淡海、安坑輕軌沒有班距表；`FirstLastTimetable` 另外抓了 `KLRT`（152 筆）。桃園機場線（TYMC）的班距只有一段（05:30–00:30，15 分）。
4. **YouBike 站位**四個城市共 6,799 站（臺北 1,823、新北 1,614、高雄 1,520、臺中 1,842）；**路外停車場**臺北 673、高雄 757，**新北回空清單**（它不在這個端點）。
5. **垃圾車不在 TDX**，是環保局資料；遊戲已有決策 437 與參考庫 `Railway/game-art-previews/` 的前置，這份不重做。

## 2. 對照表

「五方」＝玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15，每方 1–5，順序同 NEXT_PRIORITIES §19；加權分＝Σ(權重×分)/100。排序編號指 `NEXT_PRIORITIES_2026-10-12.md` 的章節與項目。**授權**欄：TDX＝政府資料開放授權條款第 1 版，署名「交通部運輸資料流通服務平臺（TDX）」（遊戲 `DataSourceCredits` 已有 TDX 一行）；底層資料各自有單位，依該資料集頁面。

| 生活168 的資料類 | 官方端點／來源 | 授權 | 遊戲已有／缺 | 用在哪個排好的項目 | 玩 | 開 | 美 | 鐵 | 音 | 加權 | run |
| --- | --- | --- | --- | --- | --: | --: | --: | --: | --: | --: | --- |
| 公車路線、站牌、站序、形狀、班距 | `/api/basic/v2/Bus/Route`、`StopOfRoute`、`Shape`、`Schedule` `/City/<縣市>` | TDX | **已有**（22 縣市，決策 400 10i-3，由 TDX 與參考庫來）。這次再抓臺北與新北原始檔留底 | §22.13 第 2 項（獨立市區公車） | — | — | — | — | — | — | 165–168、171 |
| 公車**實際班次**（每班起站發車時間、星期） | 同上 `Bus/Schedule`，欄位 `Timetables` | TDX | **缺**：遊戲只有班距，沒有班表。臺北 35,493 班（每班只有起站時間）。其他縣市沒抓 | §22.13 第 2 項（派工單 AB）：每天班次數與尖離峰班距照班表 | 4 | 4 | 1 | 4 | 1 | 3.10 | 166 |
| 公車首末班、營運業者、票價說明 | `Bus/Route`（`SubRoutes[].FirstBusTime/LastBusTime`、`Operators`、`TicketPriceDescription`）、`Bus/Operator/City/*` | TDX | **缺**：遊戲的路線沒有首末班與業者名 | §22.13 第 2 項（路線卡的營運時間） | 3 | 3 | 1 | 4 | 1 | 2.55 | 167、194 |
| 公車票價 | `Bus/RouteFare/City/<縣市>` | TDX | **缺**：遊戲全是一段 $5。臺北 722 筆（階段票）、高雄 303 筆（起迄站）；其他縣市沒抓 | §22.12 第 9 項（真實票價）、§22.13 第 2 項（票價調校：實測的 NT$15） | 3 | 3 | 1 | 4 | 1 | 2.55 | 180、181 |
| 公車即時到站、車輛位置 | `Bus/EstimatedTimeOfArrival`、`RealTimeNearStop`、`RealTimeByFrequency`（basic）；歷史版在 `/api/historical/`（本次不碰） | TDX | 即時的沒抓（每秒變）。歷史樣本已在 `Railway/tdx-bus-history-2026-10/` | 只能給畫面層（街景公車跟實況）；GameCore 不吃即時資料（決定性） | 2 | 2 | 2 | 4 | 1 | 2.15 | 192（取 3 筆確認欄位：`StopStatus`、`UpdateTime`） |
| 台鐵時刻、誤點 | `Rail/TRA/DailyTrainTimetable`、`TrainLiveBoard`、歷史 `LiveTrainDelay` | TDX | **已有**：時刻在遊戲，誤點 285 天在 `tdx-snapshot-2026-10/`（派工單 M、M2、M3） | §22.17（誤點分析兩張） | — | — | — | — | — | — | 未查（已有） |
| 高鐵時刻、票價 | `Rail/THSR/*`（`ODFare`、`DailyTimetable`） | TDX | **已有**：票價表在 `taiwan-rail-reference-clean/source/data/thsr_fare.json`，決策 325 已用 | 無新增 | — | — | — | — | — | — | 未查（已有） |
| 捷運班距 | `Rail/Metro/Frequency/<TRTC|KRTC|TYMC|TMRT|NTMC>` | TDX | **部分有**：遊戲的捷運班次來自參考庫的實際班表（`tools/real-timetables/extract_metro_runs.py`）。官方班距表可當對帳：臺北 22 筆（分平日／假日、尖離峰）、高雄 8、桃園 1、臺中 2、新北環狀 4。**高雄輕軌、淡海、安坑沒有此表** | 決策 400 的捷運班次對帳；§22.12 第 9 項之外不另排 | 3 | 3 | 1 | 5 | 1 | 2.70 | 173、175、177、183、185（179 被拒） |
| 捷運／輕軌首末班車 | `Rail/Metro/FirstLastTimetable/<TRTC|KRTC|TYMC|TMRT|NTMC|KLRT>` | TDX | **缺**（遊戲的營運時段來自班表，沒對帳）：臺北 245、高雄 304、桃園 160、臺中 34、新北環狀 70、高雄輕軌 152 筆。淡海、安坑輕軌沒試（UNVERIFIED，端點可能同樣拒絕） | 同上 | 3 | 3 | 1 | 5 | 1 | 2.70 | 172、176、178、182、184、186 |
| 捷運出口、設施、票價 | `Rail/Metro/StationExit`、`StationFacility`、`ODFare` | TDX | **臺北出口與設施已有**（`tdx-snapshot-2026-10/`）。其他系統見 `tools/not_fetched_yet.json`（約 52 個不扣點 run，未抓） | 不另排；不扣點清單另派 | — | — | — | — | — | — | 未查 |
| YouBike 站位與車位數 | `Bike/Station/City/<縣市>`（靜態位置、`BikesCapacity`）；`Bike/Availability`（即時借還數，每分鐘變，沒抓） | TDX（底層：各縣市與 YouBike 業者） | **缺**。四市 6,799 站；臺北車位總數 51,765。全部是 YouBike 2.0（`ServiceType` 2） | 3D 街景的站前小道具（接 §22.12 第 4、5 項那批街景道具；§22.12 第 9 項的 YouBike 票價比較） | 2 | 3 | 4 | 2 | 1 | 2.40 | 169、187–189 |
| 路外停車場位置與車位 | `Parking/OffStreet/CarPark/City/<縣市>`（`/api/basic/v1/`）；剩餘車位在 `.../ParkingAvailability/`（即時，沒抓） | TDX（底層：各縣市交通局） | **缺**。臺北 673、高雄 757（含位置、地址、費率文字、機車／充電旗標）；**新北回 0 筆**，臺中、桃園沒試 | 10d（自有建築新種類：停車場當城市建物）與站前街景 | 2 | 3 | 3 | 1 | 1 | 2.10 | 170、190、191 |
| 國道路況、CCTV | `Road/Traffic/CCTV/Freeway`（取 3 筆確認）、`Road/Traffic/Live/Freeway` | TDX（底層：高速公路局） | 無。CCTV 只給影像串流網址與位置，即時影像不存；路況沒查 | §22.12 第 8 項（街上車流曲線）的資料來源可選這個，**先不排**（路況端點沒查，UNVERIFIED） | 1 | 2 | 1 | 1 | 1 | 1.25 | 193 |
| 垃圾車即時位置與路線 | **環保局各自的開放資料**（雙北：臺北市環保局、新北市環保局；其他縣市各自）；**不在 TDX** | 政府資料開放授權條款第 1 版（依各資料集頁面，data.gov.tw 查） | 決策 437（垃圾車）已在做；音樂〈給愛麗絲〉在 §22.12 第 2 項 | §22.12 第 2 項（已排） | 3 | 4 | 1 | 1 | 5 | 2.95 | 不查 |
| 空品 AQI、統一發票、樂透、手電筒等小工具 | 環境部、財政部、台灣彩券 | — | **不用**：與鐵道、城市經營無關（NEXT_PRIORITIES §22.12「不拿」也已列空氣品質） | — | 1 | 1 | 1 | 1 | 1 | 1.00 | 不查 |

**怎麼打這些分**（一行一方）：玩家——能不能讓玩家看到、玩到；開發——資料乾淨度、能不能 Linux 測、要不要動 GameCore；美術——能不能變成畫面；鐵道迷——真實度與出處；音樂——只有垃圾車有。

## 3. 五方（最值得做的兩件）

**A. 實際班次＋票價進獨立市區公車（派工單 AB，§22.13 第 2 項）**
- **玩家**：路線卡寫得出「首班 05:10、末班 22:20、尖峰 7–12 分一班」和真實票價，像台灣的公車。
- **鐵道迷**：資料是官方的，不是猜的；一段 15 元與遊戲 $5 的換算（NT$3＝$1）有表可證。
- **開發**：班表只有起站時間，要自己推每站時間；只需在建檔時用工具壓成「時段→班距」，不用進 GameCore。`Timetables` 臺北 12 MB 原始，壓一壓遠小於 1 MB。
- **美術**：無。
- **音樂**：無。

**B. YouBike 站與路外停車場進街景**
- **玩家**：站前街口有 YouBike 架、附近有停車場，城市比較像真的。
- **鐵道迷**：無。
- **開發**：位置清單直接可用；只畫在 `.close`；不進 GameCore。
- **美術**：台灣特有的橘色 YouBike 架與立體停車場外觀，一眼是台灣。
- **音樂**：無。

## 4. 沒選的

- (A) 把即時到站接進 GameCore：違反決定性，且資料每秒變；改成畫面層才可以。
- (B) 抓所有縣市的公車班表與票價：臺北已足夠驗證格式；高雄票價原始 36 MB；整批抓等 AB 確定要哪些縣市再抓。
- (C) 抓 `/api/historical/`：作者交代不碰（會扣點，11/1 重置）。

## 5. 方法與驗證

- 全部走 `.github/workflows/tdx-check.yml`（`actions_run_trigger`，ref `main`，一次一個路徑，最多同時 3 個）。**只問 `/api/basic/`**；金鑰沒看、沒貼、沒存。共 **36 個 run（#159–#194）**：先 `$top` 小樣本確認欄位（159–164、174、192–194），再抓整份（165–173、175–178、180–191）。run 179 被 TDX 拒絕（400，`KLRT` 不在 Frequency 的清單）。run 對路徑的完整對照在私庫 `Railway/tdx-live-2026-10/00_READ_ME_FIRST.md` 與 `tools/requests.json`。
- 記錄的數字是抓回來的資料量出來的（`python3 -I tools/verify.py` 通過）；「遊戲已有」的判斷讀了 `tools/real-buses/README.md`、`RailwayGameApp/Resources/RealBuses/`、`docs/research/CITY_BUS_ROADS_DESIGN_2026-10-27.md`、HANDOFF 與私庫 `tdx-snapshot-2026-10/`。
- 參考庫比對：`Railway/tdx-snapshot-2026-10/`、`Railway/tdx-bus-history-2026-10/` 讀過；`tools/not_fetched_yet.json`（捷運其他系統的線形／出口／設施／行駛時間，台鐵車種與路線，高鐵站表）這次沒抓，與本表不重複。
- 搜尋範圍：生活168 首頁（只讀工具清單，不抄）；TDX 官方端點。外部開源專案：沒找，也不需要——這次沒寫任何程式。
- 沒驗證的（UNVERIFIED）：生活168 各工具頁與指南的內文；`Road/Traffic/Live/Freeway`、`Bike/Availability`、`ParkingAvailability`、其他縣市的 Bus、淡海／安坑輕軌的首末班端點。
- `python3 -I tools/golden-checks/doc_numbers.py --check`：VERIFIED（本機 Linux，差異 0 項）。其餘檢查（Swift、iOS）不適用：只加一份文件。
