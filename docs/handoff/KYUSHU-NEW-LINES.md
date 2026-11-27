# KYUSHU-NEW-LINES：日本地圖加三條可以買的線

## 進度

- 做到哪：第一張（RELAY-KAMOME-LINE，海鷗接力號，決策 1028）合併；第二張（山陽新幹線，決策 1029）由接手串做完；**第三張（決策 1030）還沒開工，要再開一串**。
- 已驗證：`RelayKamomeTests`、`SharedStationLayoutTests.testTheRelayKamomeMeetsTheKamomeAcrossThePlatform`、福岡與九州新幹線、西九州新幹線的測試與一天體檢（數字見決策 1028 §4 與 `CheckupBudgets/Fukuoka.swift`）。
- 下一步的第一個指令：讀 `docs/priorities/SHINKANSEN-EXTEND.md`（素材庫 -2）與本檔下面兩節，再讀 `real-line-laying`、`depot-work` 兩個 skill。

## 登記

- 派工：規劃 4，#595（SHINKANSEN-EXTEND）、#596（RELAY-KAMOME）。
- 分支：`claude/project-thread-xm8e8h`（第一張）；接手的串用自己的分支。
- 決策號：1028（海鷗接力號，已用）、**1029（山陽新幹線博多—小倉）、1030（九州新幹線熊本—新水俣）保留給接手的串**（#2118 的登記）。
- 存檔版本、golden schema：不動（延伸段另外賣，不改已買的線，所以不用升存檔版本）。

## 第一張做好、可以直接用的

- `build_kyushu_shinkansen.py merge <暫存> <地圖包>` 已改成通用：任何系統的暫存資料夾都能併（`MERGED_SYSTEMS`、`LINE_ORDER`），重跑已併的系統得到一模一樣的檔。新系統要加進 `build_fukuoka_rail.py` 的 `LINE_ORDER` 與 `extract_fukuoka_runs.py` 的讀檔清單。
- 新系統要動的地方（照 `jrkyushu` 改過的檔一一對）：`OverseasMap.fukuoka` 的 systems、`overseasOthers`（系統名與線色）、`overseasLines`（等級、車種）、`DemoRealLines.cars(ofSystem:)`、`Map3DRealTrains`（`Map3DRealTrainsJapan.swift`）、`Map3DOverheadLine.wiredSystems`、`Map3DViaducts`、`TrackGauge.ofRealLine`（GameCore，會讓 PR 跑全部的 CI）、`DataSourceCredits+Fukuoka.swift`，以及測試裡的系統與綁售清單（`KyushuShinkansenTests`、`FukuokaRailwaysTests`、`RealLineBundleTests`、`DemoRealLinesEverySystemTests`、`RealRailwaysTests`、`FukuokaGroundTests`、`TimetableCheckupAllBoughtTests`、`SharedStationLayoutTests.testReport`）。
- 共站的量法：`SHARED_STATION_REPORT=<檔> SHARED_STATION_ONLY=kamome swift test --skip-build --filter SharedStationLayoutTests.testReport`（`SHARED_STATION_PROFILE=<線>` 印整條線的高度）。全部的線都買要很多錢：`FukuokaRailwaysTests.fukuoka(balance: RelayKamomeTests.everyLine)`。
- 教訓（real-line-laying §4 第 1028 列）：真實月台在高架而 OSM 沒標，後買的地鐵會被擋；端點站的月台以站點為中心，N02 的點不一定在月台上。

## 第二張：SANYO-SHINKANSEN-KOKURA（決策 1029，評分 2.85）

**做完**（接手串「鋪設山陽與九州新幹線延伸」，決策 1029）：系統 `sanyoshinkansen`、線 `SY`，55.96 km、整天每 15 分一天 138 班（估計）、16 節 N700S／700 系、沒有機廠、單獨賣、只在寫實規則賣（中間沒有站，簡單規則會一直誤點，同台灣高鐵）。
博多最後買時原本被推到地底空港線上面，改成高架站不算地底的公司軌道（`sharedEnds` 的 `raised`）。留下的：博多総合車両所當機廠、直通九州新幹線的班次、簡單規則也能賣（要改 GameCore 派車）。
下面是原本的交接：

**博多共用月台（作者 2026-11-27：「還是要改共用 為未來直通做準備」）還沒做**，要另開一張（本串已壓縮一次）。現在山陽新幹線在博多是自己 3 股、排在九州新幹線 6 股旁邊。改共用的起點：
- 遊戲裡「一條線的車開進另一條線的軌道、從月台另一端離開」只有輕軌的沙崙做過（SHALUN-ONE-ISLAND，決策 885）：`RealBranchLine.leavesAt`（現在寫死淡海藍海線）、`shares`（`overseasLines` 的第 5 欄）、`RealLineAcquisition.Joining`、`laidOfferInLanes` 的 `joining: true`。
  山陽新幹線要 `shares: "kyushushinkansen:KS"`、`leavesAt` 博多（第 0 站，沙崙是中間站，第 0 站要確認走得通），從九州新幹線博多月台線的北端接出自己的線。
- 兩個系統不同（決策 862 分開賣），`isLaidAlong` 沒查系統，但要確認 `traces.snap(... system:)` 與 `RealLineLaying.realPoint(... system:)` 用的是自己的系統。
- 買的順序：先買九州新幹線才共用；先買山陽新幹線時，九州新幹線也要能接進山陽新幹線的博多（或規定順序），不然兩種順序結果不同。
- 博多股數：九州新幹線的車在博多 2 股折返 8 分（`TRACKS_AT_LEAST`，決策 975），加上山陽新幹線 4 組（2 組在博多過夜），要重排兩條線的時刻與股數，兩種規則跑體檢；真實 11–16 號 6 股兩家共用。
- 之後的直通（KYUSHU-SHINKANSEN-EXPRESS，みずほ、さくら）會用到同一套。

- 山陽新幹線博多—小倉，約 67 km，中間沒有站，大半在隧道（新關門隧道以南的部分）。OSM route relation 1837932。
- **新系統**（JR 西日本，例如 `jrwest`），和九州新幹線不同系統，所以單獨賣（決策 862 只綁同系統）。軌距照 `TrackGauge.ofRealLine` 加成新幹線。
- 車：N700S 16 節（遊戲已有 `Map3DN700S`），隔一組用 700 系；不新建模。
- 博多和九州新幹線、地鐵空港線、七隈線、海鷗接力號共站：兩條新幹線月台並排、同一高度（3 樓，16 m），不疊。兩種以上的購買順序都跑 `SharedStationLayoutTests`。
- 機廠：真的博多総合車両所在博多南線那頭（前約 8 km 和九州新幹線共線），先照 `depot-work` skill 量格子；量不下就像熊本那樣在站外自己鋪一座並寫明。
- 小倉在遊戲裡沒有別的線（不共站）；小倉以北在山口縣，地圖沒有地面，不做。

## 第三張：KYUSHU-SHINKANSEN-MINAMATA（決策 1030，評分 2.50）

**還沒開工**（接手串「鋪設山陽與九州新幹線延伸」壓縮 1 次，照規則不接新工作；決策 1030 仍保留）。那串量到的：

- OSM 的九州新幹線從熊本 (130.687997, 32.789556) 量到新八代 31.80 km、到新水俣 74.67 km，橋與高架 38.0 km、隧道 35.4 km；N02 站點見下。
- **最大的難處是機廠**：遊戲自己鋪的熊本機廠（`RealLineDepotSite.kumamoto`，接點 (32.788870, 130.687550)、場到 32.7859，8 股）正好在延伸段要走的線上。
  已買九州新幹線的存檔裡那座機廠已經蓋好，延伸段另外賣時要從它旁邊過（`sharedEnds` 會把延伸段的熊本端推到公司軌道旁），或在延伸段改用真的富合機廠（`kyushu-shinkansen/depot.json`，13 股 288 m，接點 (130.673816, 32.716903)，在延伸段上，像台灣高鐵烏日那樣 `beyond: nil, compact: false`）。
- **另外賣**：同系統、在熊本共站，照決策 862 新局會和博多—熊本綁一起賣（已買的存檔只賣延伸段）。要真的分開賣要在 `RealLineBundle.groups` 開例外或換系統名，寫進決策。
- **簡單規則**：熊本—新八代約 10 分、新八代—新水俣約 9 分，比山陽新幹線短；班距 15 分以上應該不必像決策 1029 那樣只在寫實規則賣，但兩種規則都要跑體檢（決策 1029 §2 寫了為什麼中間沒站的線在簡單規則會一直誤點）。

- 九州新幹線熊本—新水俣，延伸段**另外賣**（建議：已買博多—熊本的存檔不用動）：新八代 (130.635383, 32.516686)、新水俣 (130.42823, 32.21025)，約 76 km。
- 地圖南緣 32.09N，新水俣離南緣約 13 km：動工前確認那裡的地面、建物、人口都有。
- 機廠可以改用真的熊本総合車両所（富合，熊本以南 8.45 km，`kyushu-shinkansen/depot.json` 已有位置與 13 股），現在遊戲在熊本站南邊自己鋪的那座（`RealLineDepotSite.kumamoto`，決策 975）怎麼處理要寫進決策。
- 延伸段和博多—熊本是同一系統、在熊本共站，照決策 862 會綁在一起賣；要「另外賣」就得當成另一條線（例如 `KS2`）並說明為什麼不綁。

## 還留下的（第一張）

- 885 系、787 系的模型（RELAY-KAMOME-TRAINS）要等作者同意；現在暫代成太魯閣（8 節，買到的是 6 節）。
- 海鷗接力號沒有機廠（南福岡車輛區），晚上停在兩端。
- iPhone 上沒看過（UNVERIFIED：要 macOS／實機）。
