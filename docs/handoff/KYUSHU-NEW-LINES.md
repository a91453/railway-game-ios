# KYUSHU-NEW-LINES：日本地圖加三條可以買的線

## 進度

- 做到哪：第一張（RELAY-KAMOME-LINE，海鷗接力號，決策 1028）做完開 PR；本串壓縮第 2 次，第二、三張交給新的工作串。
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

- 山陽新幹線博多—小倉，約 67 km，中間沒有站，大半在隧道（新關門隧道以南的部分）。OSM route relation 1837932。
- **新系統**（JR 西日本，例如 `jrwest`），和九州新幹線不同系統，所以單獨賣（決策 862 只綁同系統）。軌距照 `TrackGauge.ofRealLine` 加成新幹線。
- 車：N700S 16 節（遊戲已有 `Map3DN700S`），隔一組用 700 系；不新建模。
- 博多和九州新幹線、地鐵空港線、七隈線、海鷗接力號共站：兩條新幹線月台並排、同一高度（3 樓，16 m），不疊。兩種以上的購買順序都跑 `SharedStationLayoutTests`。
- 機廠：真的博多総合車両所在博多南線那頭（前約 8 km 和九州新幹線共線），先照 `depot-work` skill 量格子；量不下就像熊本那樣在站外自己鋪一座並寫明。
- 小倉在遊戲裡沒有別的線（不共站）；小倉以北在山口縣，地圖沒有地面，不做。

## 第三張：KYUSHU-SHINKANSEN-MINAMATA（決策 1030，評分 2.50）

- 九州新幹線熊本—新水俣，延伸段**另外賣**（建議：已買博多—熊本的存檔不用動）：新八代 (130.635383, 32.516686)、新水俣 (130.42823, 32.21025)，約 76 km。
- 地圖南緣 32.09N，新水俣離南緣約 13 km：動工前確認那裡的地面、建物、人口都有。
- 機廠可以改用真的熊本総合車両所（富合，熊本以南 8.45 km，`kyushu-shinkansen/depot.json` 已有位置與 13 股），現在遊戲在熊本站南邊自己鋪的那座（`RealLineDepotSite.kumamoto`，決策 975）怎麼處理要寫進決策。
- 延伸段和博多—熊本是同一系統、在熊本共站，照決策 862 會綁在一起賣；要「另外賣」就得當成另一條線（例如 `KS2`）並說明為什麼不綁。

## 還留下的（第一張）

- 885 系、787 系的模型（RELAY-KAMOME-TRAINS）要等作者同意；現在暫代成太魯閣（8 節，買到的是 6 節）。
- 海鷗接力號沒有機廠（南福岡車輛區），晚上停在兩端。
- iPhone 上沒看過（UNVERIFIED：要 macOS／實機）。
