# SHINKANSEN-SALE 交接（九州新幹線上架，決策 975）

派工單：私有 repo `docs/priorities/JAPAN-KUMAMOTO.md` 第 4 列（2.90）。分支 `claude/project-thread-qgz3bv`。
決策 **975**（#2118 已登記，**檔還沒寫**）。存檔版本、golden schema：不動。動到 GameCore 一行（`TrackGauge.ofRealLine`），所以 CI 跑整輪。

**這一串在對話壓縮第二次時依規定停手（2026-11-25），沒做完。** 下面是接手的人需要的全部。

## 進度

- 做到哪：資料已併進地圖包、程式已接上；**只買新幹線**時能出價、買得成、86 班都發得出去。**先買地鐵三條線再買新幹線會被擋**（下面「沒解的事」第 1 點），釘住的測試、決策檔、文件都還沒改，所以草稿 PR 是紅的，**不能合**。
- 已驗證（雲端 Linux，Swift 6.4.0，debug）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨（最後一次改動只是拿掉除錯碼，推之前又建了一次）；`TrackGaugeTests`、`FukuokaGroundTests`、`RealRailwaysTests`、`PlatformNameBoardStylesTests` 當時跑過。下面「量到的數字」是 `KS_PROBE=1 KS_ORDERS=1 swift test --skip-build --filter KyushuShinkansenProbeTests` 與 `TIMETABLE_CHECKUP=1 swift test --skip-build --filter TimetableCheckupAllBoughtTests/testFukuokaShinkansen` 印出來的。**其餘一律 UNVERIFIED**（整輪測試沒跑過，一定有釘住「三條線、一個系統」的測試會紅）。
- 下一步的第一個指令：`KS_PROBE=1 swift test --skip-build --filter KyushuShinkansenProbeTests 2>&1 | grep "^KS"`（三種購買順序都跑，約 3 到 5 分鐘），看「地鐵先、新幹線後」那一組的 `problem`。

## 做了什麼

- **資料**（不要重跑 `build_fukuoka_rail.py` 整包，也**不要重生地面檔**；只用 `merge`）：
  `python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka`
  把暫存的新幹線併進 `track_lines.geojson`（4 條）、`track_stations.geojson`（45 站）、`rail_structures.json`（105 筆）、`station_names.json`、`pack.json`，
  並放進 `kyushushinkansen.json`、`kyushushinkansen_times.json`。之後 `extract_fukuoka_runs.py` 排兩個系統的 `metro_runs.json`
  （新幹線 86 班、8 組車、夜裡 8 組都在熊本；`DEPOT_ENDS` 熊本、`RECOVERY` 熊本 300 秒）。`build_fukuoka_rail.py` 單獨跑只寫地鐵，所以每次重寫鐵道檔後要再跑一次 `merge`。
- **第二個系統**：`OverseasMap.systems`（福岡 = `fksubway` 加 `kyushushinkansen`）、`OverseasMap.map(ofSystem:)`；`RealRailways` 的載入與 `system(_:)`、
  `DemoRealLines`、`StationStamps`、`RealLineAcquisition.standsOnItsOwnPoints` 都改問它。`RealRailways.System.overseasOthers` 放 JR九州（顏色 `#C8102E`）。
  待售清單多一列 `("kyushushinkansen", "KS", "Kyushu Shinkansen", "九州新幹線", nil, .metro, false)`。組合是一個系統一組，所以新幹線**單獨賣**。
- **高鐵車與月台**：`DemoRealLines.trainType` 與 `cars(ofSystem:)` 把 `kyushushinkansen` 當 `.highSpeed`、6 節；`RealBranchLine.platformLength(real:)`
  在高鐵車時取「標準算法」與「真實車長」較長的（海外圖車長是真的，6 × 25 m = 150 m，原本的 `(節數+1)×16 m` = 112 m 太短，一班都發不出去）。
  `build` 裡高鐵車的線 `setLinePerformance(.highSpeed)`（速度、票價、腹地、110 秒停站照決策 168）。
- **深隧道**：`TrackPlan.init` 的 `split` 多一個條件 `low`（一段的高差不超過 GameCore 的 128 m，`TrackRise.greatestEdgeRise`）；超過時允許把切點放在離地面 60 m 以下、1,000 m 以內
  （`TrackRise.allowsDeepNode`）。原因：筑紫隧道有一段 6.3 km 降 160 m，原本的規則不肯在地面下 60 m 以外放節點，整條線被 `invalidTrackGeometry` 擋掉。GameCore 原本就收的邊行為不變。
- **機廠**：`RealLineDepotSite.kumamoto`（熊本車輛基地，緊接熊本站南邊，8 股，`beyond: "熊本"`，`compact: true`）。真實的熊本総合車両所在再往南 8.45 km 的富合，
  待售的線只到熊本站，所以照橋本（決策 898）的做法放在站過去；`tools/fukuoka-map/kyushu-shinkansen/depot.json` 留著當紀錄。
- **軌距**：`TrackGauge.ofRealLine` 把 `kyushushinkansen` 當新幹線軌距（GameCore，`TrackGaugeTests` 加一條）。
- **資料來源**：`DataSourceCredits` 多一筆 `kyushuShinkansen`（N02 CC BY 4.0、OSM ODbL、與 JR 九州無關）。
- **站名牌**：`PlatformNameBoardStylesTests` 的站號檢查只看 `fksubway`；新幹線站沿用決策 882 的站名牌（日式新幹線站名牌要新字形，沒做）。
- **測試**：`Tests/GamePresentationTests/KyushuShinkansenTests.swift` 現在只是**量測用的探針**（`KS_PROBE=1` 才跑，結果寫到 stderr，`print` 在 `swift test` 底下看不到）。
  合併前要換成真的測試或刪掉。`TimetableCheckupAllBoughtTests.testFukuokaShinkansen` 已加，還沒有預算數字。

## 量到的數字（只買新幹線，從 2 × 2 塊的新局）

- 出價約 12 秒。擁有的地圖塊 4 → 11（**跟著線買了 7 塊**，決策 401 在海外圖上有效）。清單上的距離 `metres` 4609、`note` nil。
- 價錢：土地 39,060,000,000、建造 22,946,797,583、列車 3,600,000,000。8 組 6 節高鐵車。
- 7 站都在高架上（離地約 16 m）；熊本 5 股、博多 1 股、其餘 2 股。機廠 8 股。軌距印出 `[standard rails, shinkansen loading]`。沒有死結、沒有疊站。
- 跑一整天（`testFukuokaShinkansen`）：
  - 簡單規則：沒發 0、晚點 24 班（最晚 20.7 分）、出庫 14 班（晚 0）、尖峰班距 +20.7 分（熊本 18:20，35.7 對 15.0）。
  - 擬真規則：沒發 0、晚點 22 班（最晚 20.4 分）、出庫 16 班、尖峰班距 +5.4 分（博多 18:05，35.4 對 30.0）。

## 沒解的事（照這個順序做）

1. **先買地鐵三條線、再買新幹線：出價約 36 秒後被拒**，訊息是「這段軌道會與另一段軌道交叉，但兩者的高度差不到 8 公尺…」。猜是博多站一帶新幹線高架下來與地鐵隧道口、或共站的處理（`RealLineSharedStation`）；
   還沒找到是哪一段。找法：在 `RealLineAcquisition.build` 的 `lay` 裡、鋪每一片（`piece`）之前，用 `var trial = world` 一段一段 `buildTrackEdge`，接到錯就印出那一段兩端的座標與地面高，
   看它在哪。動手前先讀 `.claude/skills/real-line-laying/SKILL.md`（決策 848：兩條線同站要並排同高，不能疊）。「新幹線先、地鐵後」那個順序在修好月台長度之後還沒重量。
   如果博多的共站一時做不對，最簡單的拍板是：新幹線的博多站自成一站、不和地鐵共站（JR 博多站與地鐵博多站本來就是兩棟），寫進決策 975。
2. **晚點 22 到 24 班**。還沒找原因。候選：博多只有 1 股、折返 12 分；8 組車早上全從機廠出來（橋本的算法會是「夜車數 −（端站股數 − 1）」= 4 股，現在給 8 股）；時刻表的停站 60 秒對擬真的 110 秒。
   先讀 `.claude/skills/depot-work/SKILL.md`。修到合理後在 `Tests/GamePresentationTests/CheckupBudgets/Fukuoka.swift` 寫預算；修不動就照量到的數字寫預算、原因寫進決策。
3. **釘住舊數字的測試**（一定會紅，逐一看是該改期望值還是真的壞了）：`RealLineBundleTests`（約第 64 行）、`RovaniemiReportTests`（約 55）、
   `TimetableCheckupAllBoughtTests`（約 169、186 與「待售」清單）、`DemoRealLinesEverySystemTests`（67 個系統的集合）、`FukuokaRailwaysTests.testEachLineIsBoughtAndRunsADay` 的待售清單，
   可能還有地圖包大小、manifest、`rail_structures` 的系統。`RealLineBoughtAgainTests`、`SharedStationLayoutTests`（博多兩種順序）要加新幹線。
4. **真的測試**取代探針：單獨買（買到的地、清單距離、7 站、機廠名與股數、軌距、高鐵規則）、與地鐵兩種順序。
5. **文件**：`docs/decisions/975.md`（五個角度各一行、對照表、查了什麼）；`tools/fukuoka-map/README.md` 的「九州新幹線（暫存）」一節還寫「遊戲不讀」，要改；
   `real-line-laying` 與 `depot-work` 兩個 skill 的經驗列；`Sources/GamePresentation/WhatsNewNext.swift` 加一行「這版新增」；跑 `python3 -I tools/golden-checks/doc_numbers.py --check`。
6. 私有 repo `docs/priorities/JAPAN-KUMAMOTO.md` 第 4 列標已做（`python3 tools/asset_guard.py --base origin/main`，PR，`guard` 綠自合）。
7. 遊戲的 PR 等 `Swift CI (gate)` 與 iOS build 都綠才合，合完在 #2118 釋出決策 975。

## 不要做的事

- 福岡包的地面檔（高度、水域、陡坡、建物）**不要重生**。
- 另一串在改描線（拖曳描線更順），描線相關檔盡量別碰；這張單沒碰。
- 作者不想被問設計選項：自己拍板最簡單的做法，回報時用白話講玩家看到什麼。
