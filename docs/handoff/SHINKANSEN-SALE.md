# SHINKANSEN-SALE 交接（九州新幹線上架，決策 975）

派工單：私有 repo `docs/priorities/JAPAN-KUMAMOTO.md` 第 4 列（2.90）。分支 `claude/project-thread-qgz3bv`，草稿 PR #2681。
決策 **975**（#2118 已登記，**檔還沒寫**）。存檔版本、golden schema：不動。動到 GameCore 一行（`TrackGauge.ofRealLine`），所以 CI 跑整輪。

**第二串（SHINKANSEN-SALE-2）在對話壓縮第二次時依規定停手（2026-11-25），沒做完。** 上一串留下的兩個難題都解了，剩下的是測試、文件與收尾。

## 進度

- 只買新幹線、先買地鐵再買新幹線、先買新幹線再買地鐵，**三種順序都買得成**；一天 86 班都發得出去，簡單與擬真規則都 **0 班晚點**。
- 釘住舊數字的測試、真的測試、決策檔、文件都還沒做，所以草稿 PR 還**不能合**。
- 已驗證（雲端 Linux，Swift 6.4.0，debug）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨（最後一個提交只改了一段註解與 Python 的說明，之後沒再建）；
  資料管線重跑一次（`times` → `merge` → `extract_fukuoka_runs.py`，在暫存資料夾）與提交的檔逐位元相同；下面「量到的數字」來自探針（`KyushuShinkansenProbeTests`）與 `TIMETABLE_CHECKUP=1 … testFukuokaShinkansen`。
  **其餘 UNVERIFIED**（整輪測試沒跑過）。
- 釘住測試的試跑結果：見文末「釘住測試試跑」。

## 這一串做了什麼

1. **先買地鐵再買新幹線被「高度差不到 8 公尺」擋掉 → 修好。**
   原因：共站的規則（`sharedEnds`）把新幹線的博多站搬到地鐵空港線月台旁邊（約 56 m 外，真的站在 66 m 外）；搬過去的那一段找不到自己的高架資料，
   就往下降到地鐵月台的高度（地下約 10 m），在那裡和空港線的軌道同高交叉。
   修法（`RealLineAcquisition.swift` 的 `standsOverATunnel`，`RealLineSharedStation.swift` 的 `platformsAreUnderTheGround`）：
   線的站在自己真實的高架上、而公司那一站的月台**全在地下**（離地半個交叉淨空以下）時，不把站搬過去。高架和隧道互不相擋，真的博多站也是這樣：新幹線在高架上、地鐵在地下。
   量到：三種順序博多的新幹線月台都在高架上（z 19.8 m，離地約 16 m）；`stacked` 空；`uneven` 只有「博多」（同一站兩層，新幹線高架、地鐵地下，差約 30 m）——**這是故意的**，要寫進決策 975 與 `SharedStationLayoutTests` 的期望。
   新幹線與空港線月台的距離：地鐵先買 20.4 m、新幹線先買 43.3 m。
2. **一天晚點 22–24 班 → 0 班。**
   原因：博多只有 1 股、折返 12 分，尖峰 15 分一班；下一班在新鳥栖（約 10.5 分前）就要進路，前一班還停在博多，決策 297（`runDepotEntryCandidates`）就把等著的車趕回機廠；簡單規則下還會在新鳥栖卡住。
   修法：博多 2 股（真的博多站新幹線有 4 面 8 線，取 2 股；`extract_metro_runs.py` 新的 `TRACKS_AT_LEAST`，`extract_fukuoka_runs.py` 設 `{"kyushushinkansen:KS": {"博多": 2}}`）、
   熊本以外的折返 8 分（`build_kyushu_shinkansen.py` 的 `FAR_TURN = 480`，新的 `times` 子指令只重排一天的班次，不讀 N02 與 OSM）。博多的發車因此早 4 分。
   試過沒用、已還原：決策 740 的月台清單（只管 `.travellingToStop` 的出發）、路線偏好排序。
3. **照真車改 8 節**（協調者拍板，與車輛那串 #2683、決策 977 一致）：`DemoRealLines.cars(ofSystem:)` 的 `kyushushinkansen` 8；月台跟著節數 200 m，機廠股長相同。
4. 一天的預算寫進 `Tests/GamePresentationTests/CheckupBudgets/Fukuoka.swift`（兩種規則都 0／0／0、尖峰班距 2 分）；
   `TimetableCheckupAllBoughtTests.testEveryLineOnSaleIsPlayed` 的福岡清單多 `kyushushinkansen:KS`。

## 量到的數字（8 節，只買新幹線，從 2 × 2 塊的新局）

- 出價約 12.6 秒（地鐵先買再買新幹線 15.0 秒、新幹線先買 10.7 秒）。擁有的地圖塊 4 → 11。清單距離 `metres` 4609、`note` nil。
- 價錢：土地 39,060,000,000、建造 22,986,337,457、列車 4,176,000,000。8 組 8 節高鐵車。
- 7 站都在高架上（離地約 16 m）。`metro_runs.json` 的股數：博多 2、熊本 5、其餘 1（鋪好的中間站股數這一串沒再數，上一串量到的是 2）。月台 200 m。機廠「熊本車輛基地」8 股。死結 0。
- 一天（簡單與擬真都一樣）：沒發 0、晚點 0、出庫晚點 0、從機廠出來 10 班、尖峰班距 +1.7 分（熊本 17:16，16.7 對 15.0）。

## 還沒做的事（照這個順序）

1. **釘住的測試**：照文末「釘住測試試跑」的 5 個紅逐一改（4 個是改期望值，`DemoRealLinesEverySystemTests` 第 80–81 行要真的處理）。這次的篩選沒涵蓋全部測試，CI 整輪跑時可能還有別的。
2. **共站測試**：`SharedStationLayoutTests`（福岡那段約第 254 行）加新幹線與地鐵兩種順序：`stacked` 空、`uneven` 只有博多；`testReport`（約 328 行，福岡的順序約 384 行）加新幹線的順序；
   用 `SHARED_STATION_REPORT` 比較改前（`origin/main`）改後，**其他地圖要一字不差**。`RealLineBoughtAgainTests` 加新幹線。再跑 `real-line-laying` skill §2 列的鋪線測試
   （`RovaniemiRailwaysTests`、`RealLineAcquisitionTests|RealLineRebuildTests|HongKongEveryLineTests|HongKongSharedTrackBuyOrderTests|LiujiaLineTrainsTests|RealLineBoughtAgainTests`）。
3. **真的測試取代探針**：`Tests/GamePresentationTests/KyushuShinkansenTests.swift` 現在的 `KyushuShinkansenProbeTests`（`testProbe`、`testWhere`、`testDay`，都要環境變數才跑，CI 會跳過）
   換成真的：單獨買（地圖塊 4 → 11、清單距離 4609、7 站離地約 16 m、博多 2 股 200 m、熊本 5 股、機廠熊本車輛基地 8 股、軌距 `.shinkansen`、高鐵規則、8 組 8 節、86 班）、與地鐵兩種順序（博多在高架上、不疊）。
   探針的用法留作參考：`KS_PROBE=1 KS_ORDERS=1`（三種順序）、`KS_WHERE=1`、`KS_DAY=simple|realistic KS_UNTIL=<秒> KS_WATCH=<秒>`（每分鐘印進路與趕車的狀態）。
4. **文件**：`docs/decisions/975.md`（第一行 `### 975. <標題>`；五個角度各一行；對照表與查了什麼；博多兩層同站；博多 2 股與折返 8 分；機廠放熊本站南邊；深隧道切點；月台 200 m；量到的數字；VERIFIED／UNVERIFIED）、
   `tools/fukuoka-map/README.md` 的「九州新幹線（暫存）」一節（還寫「遊戲不讀」，要改，含 `times` 指令）、
   `.claude/skills/real-line-laying/SKILL.md` 與 `.claude/skills/depot-work/SKILL.md` 的經驗列（後者：端站折返比「班距 − 最後一段」長時，決策 297 會把等著的車趕回機廠）、
   `Sources/GamePresentation/WhatsNewNext.swift` 的 `nextItems` 加一行（例：`Line(english: "The Kyushu Shinkansen from Hakata to Kumamoto is on sale on the Japan map.", chinese: "日本地圖可以買九州新幹線（博多到熊本）。"),`）、
   跑 `python3 -I tools/golden-checks/doc_numbers.py --check`。
5. 私有 repo `a91453/railway-assets-private-2` 的 `docs/priorities/JAPAN-KUMAMOTO.md` 第 4 列標已做（`python3 tools/asset_guard.py --base origin/main`，PR，`guard` 綠自合）。
6. 遊戲 PR：寫說明（開頭的署名行、對照表、五個角度、驗證），轉正式，`Swift CI (gate)` 與 iOS build 都綠才合，合完在 #2118 釋出決策 975。

## 怎麼重做資料（都在 repo 根目錄跑，逐位元可重現）

```sh
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py times tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka
```

`build_kyushu_shinkansen.py` 一開頭就 import osmium，要先 `pip install osmium`。

## 不要做的事

- 福岡包的地面檔（高度、水域、陡坡、建物）**不要重生**；不要重跑 `build_fukuoka_rail.py` 整包。
- 描線的檔（`RealRailwayTraces.swift`、`RealRailwayTracing.swift`、`TracePlan.swift`、`TracePreviewBuild.swift`）、`Map3DScene*`（3D 圖層登錄表那串）、`Map3DRealTrains.swift`（車輛那串 #2683）都別碰；這張單沒碰。
- 作者不想被問設計選項：自己拍板最簡單的做法，回報時用白話講玩家看到什麼。

## 釘住測試試跑

（下面由第二串在停手前補上；指令：`swift test --skip-build --parallel --num-workers 3 --filter 'DemoRealLinesEverySystemTests|FukuokaRailwaysTests|FukuokaGroundTests|RealLineBundleTests|RovaniemiReportTests|TimetableCheckupAllBoughtTests|RealRailwaysTests|PlatformNameBoard|MapPack|RealWorldMapTests|TrackGaugeTests|UndergroundStationsTests|RealUndergroundTests|RealRailwayGameplayTests|MapGrowthLayoutTests|OverseasSightsTests|AirRoutesTests|Map3DFukuokaTrainsTests|Map3DRealTrainsTests|Map3DTrainSetTests|HongKongRailwaysTests|RovaniemiRailwaysTests|FukuokaBuildingsTests|Map3DOpenEveryStartTests|Map3DMapLoadReportTests'`）

- 結果（2026-11-25，VERIFIED 雲端 Linux）：226 個測試，**5 個紅**，其餘全綠（`RovaniemiReportTests`、`FukuokaGroundTests`、`Map3D*`、`HongKongRailwaysTests`、`RovaniemiRailwaysTests` 等都過）。
  注意這次是 `--skip-build`，**用的是改 `TimetableCheckupAllBoughtTests` 之前建的測試檔**，所以第 5 個是舊期望值。
  1. `DemoRealLinesEverySystemTests.testALineOfEachSystemHasTrains`：第 66 行系統集合多 `kyushushinkansen`（改期望值）；**第 80–81 行是真的問題**：
     「kyushushinkansen|KS：畫面裡沒有同一條真實路線的兩個車站」——示範畫面（新局的 2 × 2 塊）只看得到博多一站。要嘛讓示範換一個看得到兩站的範圍，要嘛這個系統照不在起始範圍的線處理（看該測試怎麼對待其他起始範圍外的線），自己拍板。
  2. `FukuokaRailwaysTests.testEachLineIsBoughtAndRunsADay`（第 127 行）：待售清單多 `kyushushinkansen:KS`（改期望值；看這個測試是否也該買新幹線跑一天，或註明由 `testFukuokaShinkansen` 管）。
  3. `RealLineBundleTests.testEveryMapSellsItsLinesThatShareAStationTogether`（第 64 行）：福岡多一組 `["kyushushinkansen:KS"]`（改期望值，新幹線單獨賣）。
  4. `RealRailwayGameplayTests.testTheBundledDataLoadsWithoutIssues`（第 46 行）：系統數 13 → 14（改期望值與說明文字，加上 Kyushu Shinkansen，決策 975）。
  5. `TimetableCheckupAllBoughtTests.testEveryLineOnSaleIsPlayed`（第 169 行）：已在這串改好（比的是 Set），重建後應該會綠，要再跑一次確認。
