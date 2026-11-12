# 真實長途客運路線

決策 706 的第一步（資料）：台灣的國道客運與跨縣市的公路客運，每條路線（一個子路線、一個方向一條）的站牌與站序、走的形狀、一週每一班的發車時刻、到各站的分鐘數、全程全票票價，打包進 App（`RailwayGameApp/Resources/RealCoaches/real_coaches.json`）。GamePresentation 的 `RealCoaches`（`Sources/GamePresentation/RealCoaches.swift`）只讀，不進存檔；測試是 `RealCoachesTests`。這一步**沒有任何規則讀它**：真實客運自動跑、和鐵路搶城際旅客的規則是決策 706 的第二步。

工具只用 Python 標準函式庫。同樣的輸入寫出同樣的位元組（跑兩次 `cmp` 相同）。形狀的取整、簡化、站牌投到形狀上，直接用 `tools/real-buses/build_real_buses.py` 的函式（`import`），所以和市區公車讀起來一樣。

## 來源

交通部 TDX 的公路客運（公路局轄管路線，`InterCity`），政府資料開放授權條款第 1 版。用 `.github/workflows/tdx-check.yml` 抓（金鑰在 GitHub secret，不進 repository、log 或 artifact；TDX 的原始回答不進 repository）。資料來源畫面的「長途客運路線」寫出處與授權（`DataSourceCredits`，`realCoaches`）。

作者的參考庫（`a91453/railway-reference-private`，`fa05338`）查過，沒有公路客運的資料可搬：

| 參考 | 內容 | 用在哪 |
| --- | --- | --- |
| `Railway/geo-scene-reference-clean/source/scripts/preprocess/preprocess-bus-routes.py` | 把 TDX 的形狀、站序、班表做成路線檔；`CITY_PRESETS` 有 `intercity`（公路客運） | 做法已經在 `tools/real-buses/build_real_buses.py`（三層找站牌、投影、算班距），這裡沿用它的幾何函式 |
| `…/geo-scene…/source/public/bus/` | 20 個縣市的路線檔 | 沒有 `intercity_bus_routes.json`（`BUY_ONLY_AND_BUSES_2026-10-24.md` §3.1 已記），所以直接向 TDX 抓 |
| `…/geo-scene…/source/src/hooks/useBusIntercityLayer.ts`、`engines/BusEngine.ts` | 公路客運圖層：讀即時 GPS、貼到路線上 | 沒有搬：要後端的即時資料，不是照班表跑 |
| `Railway/taiwan-rail-reference-clean/source/data/bus-transfer/`、`bus_stops_index.tsv` | 542 個鐵道車站 600 m 內的站牌與經過的路線（含公路客運 1,530 個方向，只有車站附近那幾站），沒有班次 | 沒有用：TDX 的 `StopOfRoute` 有整條路線的站序 |
| `Railway/tdx-bus-history-2026-10/`、`Railway/tdx-snapshot-2026-10/` | 臺北、高雄市區公車的歷史位置；軌道線形與誤點 | 沒有公路客運 |

外部開源：沒有另外找；TDX 就是原始資料，程式是本專案自己的。沒有新增依賴。

## 怎麼重跑

1. Actions → Check TDX API → Run workflow（`main`），**一次一個**，`path` 依序填：

   ```
   /api/basic/v2/Bus/Route/InterCity?$format=JSON
   /api/basic/v2/Bus/StopOfRoute/InterCity?$format=JSON
   /api/basic/v2/Bus/Shape/InterCity?$format=JSON
   /api/basic/v2/Bus/Schedule/InterCity?$format=JSON
   /api/basic/v2/Bus/RouteFare/InterCity?$format=JSON
   ```

   每次的 artifact `tdx-response` 裡的 `tdx-response.json` 改名成 `InterCity_Route.json`、`InterCity_StopOfRoute.json`、`InterCity_Shape.json`、`InterCity_Schedule.json`、`InterCity_RouteFare.json`，放在同一個資料夾（scratchpad，不進 repository；五個合計約 225 MB）。

2. 產生：

   ```sh
   python3 -I tools/real-coaches/build_real_coaches.py \
     --tdx <放 TDX 回答的資料夾> --tdx-fetched <抓的日期> \
     --output RailwayGameApp/Resources/RealCoaches
   ```

   它印出收了幾條、站牌與形狀點數、週三的班數、大小，最後列出每一條沒收的路線與原因。檔裡的 `inputs` 記著五個回答的 SHA-256。`RealCoachesTests` 寫死了這次的條數與三條路線的數字，重抓後照新的資料改（那是資料變了，不是規則）。

## 怎麼挑「城際」

TDX 的公路客運共 485 條路線、1,773 個「子路線＋方向」，大半是縣內的鄉間公車（公路局轄管，不是城際）。`Route` 的 `BusRouteType` 分兩種：

- **13 國道客運**：全收（包含臺北—基隆、臺北—桃園這種短的：它們就是和台鐵搶通勤與城際旅客的車）。
- **12 一般公路客運**：只收「站牌跨兩個以上縣市」**而且**「離第一站的直線距離到過 30 km」的方向（`HIGHWAY_REACH_METRES`）。例如臺東—花蓮海線 8119、高雄—墾丁 9188／9189／9117、宜蘭—梨山 1751。30 km 大約是相鄰兩個縣市中心的距離；試過別的門檻（TDX 的 1,861 筆站序、還沒扣掉重複與沒有班表的）：20 km 收 311 筆公路客運、30 km 213 筆、40 km 73 筆、50 km 55 筆；20 km 會收進很多相鄰鄉鎮之間的公車，40 km 以上會漏掉高雄—屏東、彰化—南投之間的線。

沒收的 932 個公路客運方向就是縣內或短程的。

## 怎麼算

- **路線**：一個 key 一條：`<SubRouteUID>_<Direction>`（`THB181801_0`）。同一個 key 的第二筆站序（同一條子路線每家業者各一筆，88 筆）與第二條形狀（3 條）不收。
- **站牌與形狀**：和 `tools/real-buses` 相同（1e-5 度的整數、Douglas–Peucker 4 m、每站存「沿形狀第幾公尺」、照站序夾成不往回），只有兩個門檻放寬：站牌離形狀最多 500 m（高雄建國客運站離它的路線 394–398 m）、形狀兩點之間最多 10 km（國道上的形狀點比較疏；超過的 3 條不收）。
- **每站另外存**：所在縣市的代碼（`stopCities`，TDX 的 `LocationCityCode`）、只上車／只下車（`stopBoarding`：1 只上車、−1 只下車、0 都可以；全是 0 就不寫）。國道客運多半「起點幾站只上車、終點幾站只下車」。
- **發車時刻**（`tripMinutes`、`tripDays`）：一週每一班在班表第一個有時刻的站的發車時間（午夜起的分鐘），與它開的日子（位元 0 是週一、位元 6 是週日）。同一分鐘的班次合成一筆。
  - TDX 的 `Timetables` 是逐班時刻。
  - TDX 的 `Frequencys`（「平日 06:20–21:00 每 15–20 分一班」，16 個方向有，都是臺北—桃園、臺北—基隆這類最密的線）：從開始時間起每「（最短＋最長）÷ 2」分鐘一班，到結束時間為止。這些班次**是推算的**，`tripsFromHeadways` 記有幾班（全部 1,088 班）。落在某個班距時段、同一天的逐班時刻視為同一批車寫了兩次，不重複算。
  - 沒有班表的方向（123 個）不收：沒有班次的客運載不到人。
- **到各站的分鐘**（`stopMinutes`，第一站是 0）：班表每班只寫幾個站的時刻。取「寫了最多站」的那一班（一樣多取最早的），有時刻的站直接用，中間的站照距離內插，頭尾沒有時刻的站照那一班的平均速度外推。沒有一班寫到兩個站，或算出來的速度不在 15–110 km/h 之間（資料裡有 11 km/h 與 127 km/h 的），改用估計速度：國道客運 70 km/h、公路客運 35 km/h，`minutesEstimated` 是 true（12 條）。
- **票價**（`fare`）：`RouteFare` 的段次票價裡，那個方向跨最多站的一段（通常是起點到終點）的全票（`FareClass` 1）裡最低的那個價格（三排座、四排座、各家業者之間取最低）。81 條沒有票價資料，不寫。
- **業者**（`operators`）：只存中文名稱的文字，給之後對塗裝用；遊戲不畫業者商標（決策 593）。

## 2026-11-12 的結果

TDX 2026-11-12 抓（`tdx-check.yml` run 43159299840 `Route`、43159055329 `StopOfRoute`、43159129519 `Shape`、43159217882 `Schedule`、43159337345 `RouteFare`）。

- 收 **715 個方向**（176 條路線）：國道客運 540、公路客運 175。33 家業者。
- 19,239 個站牌、352,563 個形狀點；一週 11,694 筆發車時刻，週三 7,311 班、週五 7,966 班、週六 6,577 班、週日 6,774 班。
- 沒收 217 個：沒有班表 123、同一條子路線的第二筆站序 88、第二條形狀 3、形狀斷了 3（6670 的三個方向，跳 35 km）。另有 932 個公路客運方向不是城際。
- **大小：3.75 MB（gzip 後 0.81 MB）**，一個檔。Linux 上 `RealCoachesTests` 的四項測試（讀檔四次）共 2.3 秒。對照：`RealBuses/` 是 12.93 MB。1,773 個方向全收會有多大沒有量。
- 抽查：國光 1818 臺北→中壢 42.2 km、51 分、NT$ 77、週三 57 班；統聯 1618F 臺北→嘉義 252.6 km、260 分、NT$ 378、週三 5 班、週日 8 班；興東 8119 臺東→花蓮 171.9 km、212 站、一天一班、NT$ 547。
- 全票每公里：中位數 NT$ 2.02（一成的路線低於 1.54、一成高於 3.1）。

## 已知限制

- **TDX 的班表不完整**：有些路線的班次明顯比業者網站少（統聯 1618 臺北→嘉義本線週三只有 1 班，其餘在 1618A／1618F 等子路線；123 個方向完全沒有班表）。這裡照 TDX 有的寫，不補。
- 班距推算的班次不是真實時刻。
- 發車時刻是班表第一個有時刻的站的時間；少數班表第一個有時刻的站不是第一站，沒有往回推。
- 過年、連假的加班車（`SpecialDays`，26 班）當成平常那幾天的班次。
- 票價是全程全票的最低價，沒有收區間票價與優惠票。
- 站名只有中文（英文站名沒收，省約 0.4 MB）；路線的去向（`headsign`）中英都有。
- 沒收市區公車裡的跨市路線（例如臺北—新北的聯營公車）：那些在 `RealBuses/`。
