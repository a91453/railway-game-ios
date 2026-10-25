# 真實公車路線

決策 400 的 10i-3：台灣的市區與縣市公車，每條路線（一個方向一條）的站牌與站序、走的形狀、班距，打包進 App（`RailwayGameApp/Resources/RealBuses/`），給 10i-4「收購真實公車路線」用。GamePresentation 的 `RealBuses`（`Sources/GamePresentation/RealBuses.swift`）只讀，不進存檔；測試是 `RealBusesTests`。

工具只用 Python 標準函式庫。同樣的輸入寫出同樣的位元組（兩次輸出 `diff -r` 相同）。

## 來源

| 地方 | 來源 | 授權 |
| --- | --- | --- |
| 新北、桃園、臺中、臺南、高雄、基隆、新竹市、嘉義市、新竹縣、苗栗、彰化、南投、雲林、嘉義縣、宜蘭、花蓮、臺東、澎湖、金門、連江（20 個） | 作者的參考庫 `a91453/railway-reference-private` 的 `Railway/geo-scene-reference-clean/source/public/bus/<preset>_bus_routes.json`（參考網站用 `scripts/preprocess/preprocess-bus-routes.py` 從 TDX 的路線形狀、站序、班表做的） | 交通部 TDX，政府資料開放授權條款第 1 版 |
| 臺北市、屏東縣（參考庫沒有） | TDX 本身：`/api/basic/v2/Bus/Shape/City/<City>`、`/StopOfRoute/`、`/Schedule/`，用 `.github/workflows/tdx-check.yml` 抓（金鑰在 GitHub secret，不進 repository、log 或 artifact） | 同上 |

資料來源畫面的「公車路線」寫出處與授權（`DataSourceCredits`，`realBuses`）。

參考庫裡的 `Railway/taiwan-rail-reference-clean/source/data/bus_stops_index.tsv`（43,363 個站牌，沒有站序）與 `bus-transfer/`（542 個鐵道車站各自 600 m 內的站牌與路線站序，只有車站附近那幾站）讀過、沒有用：臺北市的站序與站牌位置直接用 TDX 的 `StopOfRoute`，比只有車站附近的幾站完整。

## 怎麼重跑

1. 參考庫 clone 到任何地方（只要 `Railway/geo-scene-reference-clean/source/public/bus/`）。
2. 臺北市與屏東縣各三個 TDX 回答：Actions → Check TDX API → Run workflow（`main`），`path` 依序填：

   ```
   /api/basic/v2/Bus/Shape/City/Taipei?$select=RouteUID,RouteName,SubRouteUID,SubRouteName,Direction,Geometry,UpdateTime&$format=JSON
   /api/basic/v2/Bus/StopOfRoute/City/Taipei?$format=JSON
   /api/basic/v2/Bus/Schedule/City/Taipei?$select=RouteUID,RouteName,SubRouteUID,SubRouteName,Direction,Frequencys,Timetables&$format=JSON
   ```

   屏東把 `Taipei` 換成 `PingtungCounty`。每次的 artifact `tdx-response` 裡的 `tdx-response.json` 改名成 `<City>_Shape.json`、`<City>_StopOfRoute.json`、`<City>_Schedule.json`，放在同一個資料夾（scratchpad，不進 repository）。TDX 的 `Shape` 不理會 `$select`，照樣回整筆，不影響結果。

3. 產生：

   ```sh
   python3 -I tools/real-buses/build_real_buses.py \
     --reference <railway-reference-private>/Railway/geo-scene-reference-clean/source/public/bus \
     --reference-commit <參考庫的 commit> \
     --tdx <放 TDX 回答的資料夾> --tdx-fetched <抓的日期> \
     --output RailwayGameApp/Resources/RealBuses
   ```

   它印出每個地方的路線數、估計班距的數目、留下沒收的路線與大小，最後列出每一條沒收的路線與原因。每個檔的 `inputs` 記著讀的檔與 SHA-256。

要換別的縣市用 TDX（例如參考庫的資料太舊），把那個縣市從 `REFERENCE_PRESETS` 移到 `TDX_CITIES`，照第 2 步抓那個縣市的三個回答。全台 22 個縣市要 66 次 `tdx-check.yml`；要常常重抓的話，見決策 400 的「下一步」（一個手動的抓取 workflow 的提案）。

## 怎麼算

- **路線**：一個 key 一條，和參考庫一樣：`<RouteUID>_<Direction>`，有具名子路線時 `<RouteUID>_<SubRouteName>_<Direction>`。
- **站牌**：
  - 參考庫：檔裡只有站名與「沿形狀的進度」（`stopProgress`，經緯度空間的長度比例，已經照站序夾成不往回），工具照 `interpolateOnLineString` 的做法把進度換回形狀上的點。
  - TDX：`StopOfRoute` 的站牌位置，照參考庫的三層找法配到形狀（同一子路線；具名子路線找不到就用整條路線；形狀沒有子路線名就把所有子路線的站牌依 `StopUID` 合併、取最小的站序），再照 `project_stop_to_line` 投到形狀上最近的點、照站序夾成不往回（參考庫的做法，改用公尺）。
  - 輸出每站的名字與「沿形狀第幾公尺」（`stopMetres`），站牌就是形狀上那一點（`RealBusRoute.Stop.coordinate`）。
- **形狀**：座標取 1e-5 度的整數（約 1 m，參考庫本來的 5 位小數），Douglas–Peucker 簡化到 4 m 內，第一點之後每點存和前一點的差。長度照 `RealRailways.Coordinate.distance(to:)` 的同一個半徑（6,378,137 m）算。
- **班距**（整數分鐘，1–720，720 是 `BusService.longestHeadway`）：
  - 參考庫：60 ÷ 檔裡的 `frequency`（一小時幾班）。
  - TDX：照參考庫的 `calc_frequency` 算一小時幾班，但只看平日（週一到週五）的列：有 `Frequencys` 就取每列（最短＋最長）÷ 2 的平均；只有 `Timetables` 就是最多班的那個平日的班數 ÷ 第一班到最後一班的小時（不知道就 14 小時）。
  - **估計班距**：沒有班表的路線（參考庫的 `frequency` 是 0.5，它沒有班表時的預設；TDX 沒有那條路線的班表）：市（6 個直轄市與基隆、新竹、嘉義市）30 分、縣 60 分，`headwayEstimated` 是 true，遊戲要寫「估計班距」。參考庫裡真的每兩小時一班的路線也是 0.5，分不出來，一樣算估計。
- **沒收的路線**（列在輸出最後）：沒有站牌；形狀兩點之間超過 5 km（形狀斷了）；有站牌離形狀超過 150 m（站序和形狀對不上）；TDX 同一個 key 的第二條形狀（臺北市的形狀都沒有子路線名）。

## 2026-10-25 的結果

參考庫 `7b61a36`，TDX 2026-10-25 抓（`tdx-check.yml` run 40240665074、40240667712、40240669585、40240671524、40240673691、40240675597）。

- 22 個地方、6,451 條（方向），1,363 條是估計班距（21%；臺北市 989 條裡 448 條，TDX 的 `Schedule` 只有 451 個「路線＋方向」）。
- 沒收 111 條：沒有站牌 72（連江縣的分時段班次 21、高雄 12、新北 10…）、第二條形狀 14、站牌離形狀太遠 15（例如屏東幸福泰武 8、9 路的「北大武山新登山口」離形狀 6.4 km、臺北 33 繞駛大道路）、形狀斷了 10。
- 大小：22 個檔加索引共 12.93 MB（gzip 後 3.54 MB）；最大的是新北 2.45 MB、臺北 1.75 MB、臺中 1.74 MB。22 個全部讀一次在 Linux debug 約 1.4 s（`testEveryPlaceReads`），地圖只讀它碰得到的縣市（`RealBuses.places(near:within:)`）。
- 參考庫的苗栗（8 條）、臺東（8 條）路線很少，是參考庫本來的範圍，不是工具丟掉的。
