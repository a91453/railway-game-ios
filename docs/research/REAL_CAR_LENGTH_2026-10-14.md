# 各車種的真實車長（設計，2026-10-14）

NEXT_PRIORITIES 2026-10-12 §6「各車種的實際車長」、§13 第 12 名。內容目錄（決策 225，#622）的下一段，遊戲規劃 session 派工。號碼（合併 session 2026-10-14 預留）：決策 227、存檔版本 62、golden schema 不動。

2026-10-15 遊戲規劃 session 派工，設計與程式在同一個 PR。做出來的規則以 ARCHITECTURE 決策 227 為準；和這份設計不同的地方：月台卡沒有加「某車種可停幾節」那一句（列車卡本來就會寫「月台太短，容不下所有車廂」），`TrainCars.count` 加了 `carPitch` 參數並預設 16 m，讓原生 3D 的檔不用跟著改。

## 1. 問題

- 每節車廂的人數已經是真實數字（決策 66、168、169），但每節車長一律 16 m（`Train.carLength` = 1,024 世界單位，每公尺 64 單位）。
- 真車一節是 19–25 m，所以同樣長的月台，遊戲裡停得下的節數偏多，載客偏多約 1.25–1.56 倍（§6）。
- 畫面上已經每節畫 20 m（決策 205，#524），所以地圖上看到的列車比它佔的軌道長。
- 3D（F 台灣版＋「比例照真的」）也要真實車長。

## 2. 現在車長影響什麼

`Train.length` = `(節數 − 1) × 1,024`，是第一節中心到最後一節中心。GameCore 裡沒有一個地方直接讀 `carLength`，全部讀列車的 `length`：

| 用途 | 位置 |
| --- | --- |
| 月台停不停得下（唯一的判斷：月台長度 ≥ 列車長度） | `ServicePath.berths(of:length:)` |
| 到站的路線、選路偏好、方向保護 | `GameWorld` 的 `path(…length:)`、`LineRoutePreference`、`ServiceDirections` |
| 車身佔的軌道、預約、讀檔時檢查車身 | `placeTrain`、`networkTrail`、`RouteReservation.bodyStretches`、讀檔的 `isNetworkTrail` |
| 彎道限速延長一個車長 | `CurveSpeedRuns`（決策 217） |
| 排定交會、越行、待避、死結解除 | `ScheduledTraffic`、`ScheduledOvertakeTracks`、`Deadlock` |
| 路線容量（取路線上最長的列車） | `LineCapacity` |
| 機廠停得下幾列（停得下的股道數） | `Depot` |
| 旅客計畫快取的鍵 | `PassengerDemand`（只當鍵，算式不用長度） |

所以只要 `Train.length` 對，以上全部跟著對。

沒有「月台太短」的錯誤：停不下的月台不算停靠位置，結果是沒有路線，或那站不停。

月台本身存的是世界單位的長度（`TrackPlatform` 的 `start`、`end`），不存節數。「幾節的月台」只在畫面層換算（`GameSession.platformCars × Train.carLength`）。

## 3. 規則

### 3.1 每種車型有自己的車長（表上加一欄）

`TrainTypeSpec` 加 `carLength`（世界單位，整數），是連結器間距，也就是相鄰兩節中心的距離：

| 車型 | 代號 | 提案車長 | 世界單位 | 來源 |
| --- | --- | --- | --- | --- |
| 大型捷運 | A | 22.0 m | 1,408 | 地鐵 A 型車中間車（GB 50157）；台北捷運文湖線以外的高運量車 23.5 m 前後 |
| 中型捷運 | B | 19.5 m | 1,248 | 地鐵 B 型車（GB 50157 中間車 19 m，含連結器 19.5 m） |
| 輕型捷運 | C | 19.0 m | 1,216 | 地鐵 C 型（輕軌）車 |
| 線性馬達捷運 | L | 16.5 m | 1,056 | 線性馬達小型車（例：大阪、廣州 4／5／6 號線約 16.8 m） |
| 多門捷運 | D | 20.0 m | 1,280 | 多門車（例：東京的多門車 20 m） |
| 自動接駁列車 | APM | 12.5 m | 800 | 膠輪 APM（例：桃園機場 APM、文湖線 VAL256 約 12.5–13.9 m） |
| 磁浮列車 | MAGLEV | 15.0 m | 960 | 中低速磁浮（長沙、北京 S1 約 15 m） |
| 輕型單軌 | SKYRAIL | 12.0 m | 768 | 小型跨座單軌（雲軌約 11–12 m） |
| 單軌列車 | MONORAIL | 15.0 m | 960 | 跨座式單軌（重慶 2 號線、東京單軌約 15 m） |
| 蒸汽列車 | STEAM | 8.0 m | 512 | 19 世紀四輪客車（劉銘傳鐵路的小客車） |
| 高鐵列車 | HSR | 25.0 m | 1,600 | 700T 中間車 25 m（頭車 27.35 m） |
| 新自強號 | EMU3000 | 20.3 m | 1,299 | 參考庫 `fleet/catalog.json` 的 `emu3000-mid` `pitchM` 20.3（頭車 21.35） |
| （沒有車型的標準車） | — | 20.0 m | 1,280 | 和畫面上每節畫的 20 m 相同（決策 205） |

- 頭車比中間車長 1–2 m；一個車型只用一個數字（中間車）。差在一列 12 節裡是 2–4 m，月台多留一點就好。
- 換算：公尺 × 64，四捨五入到整數（20.3 m 是 1,299.2，取 1,299）。
- 數字的來源要在第二段逐一查證，寫進表上那一列的註解。查不到的（D、APM、SKYRAIL）照上表取同類真車的值，並標「推定」。

### 3.2 列車記得自己的車長（不是世界算出來的）

- `Train` 加一個欄位 `carPitch`：
  - 缺 key＝1,024（16 m），所以舊存檔的每一列車長度逐位元不變；
  - 只在不是 1,024 時寫進存檔。
- `Train.length` = `(節數 − 1) × carPitch`，呼叫端一個都不用改。
- `carPitch` 什麼時候定：
  - **買車時**：世界的 `realCarLengths` 開著，取車型的 `carLength`（沒有車型取標準車的 1,280）；關著是 1,024。
  - **改車型時**（`setTrainType`，本來就只能在列車沒放上軌道時改）：一樣依開關重定。
  - **改節數時**：不變。
- 開關之後改變，不回頭改已經有的列車（和決策 180 的車輛經濟一樣，只影響下一次買車與改裝）。列車在軌道上時長度不會變，所以車身佔的軌道永遠對得上讀檔檢查。

### 3.3 世界開關

- `GameWorld.realCarLengths`，`setRealCarLengths(_:)`，免費，不是網路指令。和決策 207、217 一樣：
  - 只在打開時存 `"realCarLengths": true`；
  - App 的新遊戲（`GameWorld.newGame`）打開；
  - 示範地圖、挑戰、教學、`GameWorld` 的新世界與舊存檔關掉。它們的月台是照 16 m 蓋的：高鐵示範 12 節的月台是 13 × 1,024，換成 25 m 就停不下。
- 第一版沒有設定介面（遊戲中切換要多一種指令日誌的編輯）。

### 3.4 月台工具

開著的世界裡，蓋月台的「幾節」改用 20 m 一節（`platformLength(cars:)` 讀世界的開關）。月台卡上寫：

> 可停 8 節（20 m 車）

選了車型時再寫一句，例：

> 高鐵列車可停 6 節

只說能停幾節，不說公尺換算的算法（UI_THEME「玩家看的文字」）。

關著的世界照舊 16 m。

### 3.5 畫面

- `TrainCars.count(length:)` 用長度除以 1,024 反推節數，換了車長就錯。改成直接讀列車的節數。
- 開著時每節照自己的車長畫；關著時照舊每節畫 20 m（決策 205）。
- 3D 與 2D 依車種畫是之後的事，這裡只讓長度對。

### 3.6 存檔

- 存檔版本 62：
  - 列車的 `"carPitch"`、世界的 `"realCarLengths"` 都只在有值時寫，舊存檔讀進來逐位元相同；
  - 只讀到 61 的 build 會丟掉 `carPitch`，列車變回 16 m，存著的車身軌道就對不上，讀檔失敗，所以升版。
- 新的 fixture：`SaveFixtures/v62-real-car-length.json`，一列 12 節高鐵、一列 4 節 B 型、一列沒有車型。
- 讀檔檢查：`carPitch` 必須是表上某個車型的 `carLength`、1,024 或 1,280；其他值讀不進來（手寫的存檔才會有）。

## 4. golden、replay、存檔 fixture 怎麼保證不動

- 有多節列車的 fixture 約 36 份：golden 10、存檔 22、replay 4。全部沒有 `realCarLengths`，列車也沒有 `carPitch`，所以每一列都是 1,024，長度逐位元相同。
- 第二段的第一個 commit 先在現在的程式上加一個測試，寫死那 36 份 fixture 裡每一列車讀進來的 `length`；之後這個檔一行不改，同內容目錄的做法（決策 225）。
- `git diff --stat origin/main -- GoldenScenarios SaveFixtures ReplayFixtures` 只能多出新的 v62 fixture，既有的檔一個都不動。
- 任何一個既有值要改，就停下來回報遊戲規劃 session，不推。

## 5. 不做的

- 頭車與中間車分開的長度：一個車型一個數。
- 已經蓋好的月台自動加長；舊世界改開真實車長。
- 車長影響價格與營運成本：維持決策 180，看節數。
- 3D、2D 依車種的外觀：外觀的那一段。

## 6. 三種做法（選 B）

| 做法 | 長什麼樣子 | 結論 |
| --- | --- | --- |
| A. 世界算長度 | `Train.length` 改成 `GameWorld.length(of:)`，依開關與車型算 | 約 40 個呼叫端要改，`TrainPlacement`、路線快取都要帶世界；開關改了，軌道上的列車長度會跟著變，車身會對不上 |
| **B. 列車記得自己的車長（選定）** | `Train.carPitch`，買車與改車型時依開關定 | 呼叫端不用改；舊存檔缺 key＝16 m，逐位元不變；在軌道上的列車長度永遠不變 |
| C. 直接改常數 | 表上的車長取代 1,024，沒有開關 | 36 份 fixture 的車身、停靠位置全部改變，舊存檔的車身對不上而讀不進來：違反「不改 golden、replay、存檔」 |

## 7. 四方

- **玩家**：月台和列車的比例對了，「蓋 6 節的月台停 6 節高鐵」這種直覺成立；舊存檔照舊。新遊戲的同一個月台載客少一點，所以要蓋長一點的月台，這是真實的取捨。
- **開發**：只動 `Train` 的一個欄位與買車、改車型兩個地方，GameCore 其他用到長度的規則全部自動跟上；有開關所以 golden 不動。
- **美術**：地圖與 3D 的列車長度終於和佔的軌道一致；高鐵 25 m、捷運 19–22 m、接駁車 12 m 的比例在畫面上看得出差別。
- **音樂**：沒有改動。

## 8. 第二段要動的檔案

| 檔案 | 改什麼 |
| --- | --- |
| 新的釘值測試（第一個 commit） | 36 份 fixture 每列車的 `length`；之後不改 |
| `Sources/GameCore/Railway/TrainTypeCatalog.swift` | `TrainTypeSpec.carLength` 與每一列的值、來源註解 |
| `Sources/GameCore/Railway/TrainLength.swift`、`Train.swift` | `carPitch`、`length`、Codable（缺 key＝1,024）、讀檔檢查 |
| `Sources/GameCore/World/GameWorld.swift` | `realCarLengths`、`setRealCarLengths`、買車與 `setTrainType` 定 `carPitch`、`newGame` 打開 |
| `Sources/GameCore/World/SavedGame.swift` | 版本 62 |
| `SaveFixtures/v62-real-car-length.json`、`SaveFixtures/README.md` | 新的 fixture |
| `Sources/GamePresentation/`：`GameSession`、`NetworkSession`（月台工具與卡片）、`TrainCars`、`TrainMotion` | 月台的節數換算、畫面 |
| 示範與挑戰（`HighSpeedDemo`、`RealWorldDemo`、`NewGame` 的教學與挑戰） | 明確關掉開關 |
| `docs/ARCHITECTURE.md`、`OVERVIEW.md`、`NEXT_PRIORITIES` | 決策 227 |

## 9. 參考

`a91453/railway-reference-private` 7888702：

| 參考 | 用在 |
| --- | --- |
| `Railway/site_archive_clean/memories/tainan-2026-09-12/fleet/catalog.json` 的 `pitchM`、`bodyM` | EMU3000 中間車 20.3 m、頭車 21.35；同檔的 EMU800 20.3、TEMU2000 20.7、莒光 20.0，之後加車型時用 |
| `Ci/` 的 `*_STOCK_MODELS` | 沒有車長欄（只有人數、節數、速度） |
| `Web/CityView/src/world/trains.js`（本 repo）的 `STOCK.length` | 城市畫面的高鐵 25 m、EMU3000 20.5 m、東京各線 20 m：和上表一致 |

外部專案：
- 這次沒有搜尋程式碼：規則是一個欄位與兩個設值的地方，沒有需要借的演算法。
- 車長的公開資料（GB 50157 的車型分類、各車種的公開規格）在第二段逐一查證後寫進註解。
