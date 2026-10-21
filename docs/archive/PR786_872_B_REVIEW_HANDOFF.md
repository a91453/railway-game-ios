# 交接：PR #786–#872 的審查，B 組（建造、真實資料、經濟）

Session：PR 審查 B 組（session_01E3oRjatcqtfWgatbqPbcr1，2026-10-21），遊戲規劃 session_01WW7o3decEv5LY59nYVqnDN 派工。審查基準 `main` **f4f1b3a**（#871 的合併）。分支 `claude/review-786-872-b`。A 組（行車控制與調度）、C 組（App 畫面、UI 測試、3D 與工具）各有自己的交接；上一輪見 [`PR755_784_REVIEW_HANDOFF.md`](PR755_784_REVIEW_HANDOFF.md) 與 [`PR816_823_REVIEW_HANDOFF.md`](PR816_823_REVIEW_HANDOFF.md)。

- 存檔版本、決策編號、golden schema：都不動。GoldenScenarios、SaveFixtures、ReplayFixtures 都沒有改。GameCore 沒有改。
- 做法：每個 PR 讀合併 diff、PR 說明與它的決策，再對照 `main` 現在的程式。#851、#815、#789、#819、#826 的 GameCore 部分我自己逐行讀；其餘分給三個唯讀的子 agent（真實構造物與描線、建造與旅客的畫面、運量資料與 TDX workflow），它們的每一項發現都由我在 `main` 上重跑確認。
- 以下 **VERIFIED** 都是 Linux 雲端容器、官方 Swift **6.4.0**（`/opt/swift`）實跑；不代表 iOS 或實機。

## 一、每個 PR 一行

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #789 決策 275 | `GameWorld.editTrackAsOne`、`trackEditDepth`、`LevelPlatformTrack` 改成一次編輯 | 沒有問題：丟出時 draft 整份丟掉，世界不變；`abandonUnservedPassengers` 只在最外層跑一次。 |
| #805 決策 279 第 1 步 | `RealRailStructures`、`TrackRise` 的上下限與衝突、瑞芳／平溪示範、國土測繪中心的資料來源 | 沒有問題；資料來源有 NLSC 73220／73221（政府資料開放授權第 1 版）與 OSM ODbL。 |
| #807 第 2 步 | 宜蘭線示範照地形、`TrackPlan(beside:)`、逐段計價 | 沒有問題。 |
| #808 第 3 步 | 描線帶 `carried` 的條件（已讀地形、自動構造、高度 0） | 沒有問題。 |
| #809 第 4 步 | `rail_structures.json`、每 16 m 取樣比對、pbxproj、資料來源 | **B1**（P2，已修）。 |
| #812 決策 281 | 地下站、`heightFit`、左營引上線的順序 | 沒有找到有力證據的問題。 |
| #814 | 描線預設單、複線：memo 的 key、切換、平手算複線、兩種語言 | 沒有問題。 |
| #815 決策 282 | `keptSections(of:part:from:)`、切開後的公司建物檢查 | 沒有問題：先算兩段、檢查完才改網路，拒絕時世界不變。 |
| #817 決策 284 | `lineDraftGap`、`tracksMeet`、短月台的文字 | 沒有問題：月台長度判斷和 GameCore 的 `berths(of:length:)` 相同；兩種語言一致。 |
| #818 決策 285 | `DoubleTrackPlatform`、`addNetworkPlatform`、`PlayerCommand.addPlatform` 與它的 Codable、✓ 的價錢 | **B2**（P2，已修）。指令本身全有或全無。 |
| #819 決策 286 | `isSightseeing`、`sightseeingStops()`、`starsPerSightseeingTrain`、藍皮解憂號的目錄列 | 沒有問題：站的順序照 `stations`，與 `Set` 的走訪順序無關，決定性沒問題；星等進了旅客計畫的 key。 |
| #826 山嵐號 | 目錄列照海風號的數字、塗裝、3D 模型對照 | 沒有問題。 |
| #833 決策 289 | `BranchLineChallenge`、啟動、站長建議、`Goals` 的計算與兩個測試檔 | 沒有問題：目標量得到也達得到。里程碑 `.connect` 有站有線、沒有軌道也算達成，那是劉銘傳就有的 GameCore 規則，不是 #833 造成。 |
| #792 決策 276 | `TripStamp`、`noteActions` | 沒有問題：`GameTime` 是絕對秒數，跨午夜不會繞回；回送、中斷、貨運與自己時刻表的車照決策跳過。批次一步內起訖的行程不蓋章，決策已寫明。 |
| #795 決策 276 第二個 PR | `journeyTrace(ofLine:)`、`JourneyTrace(line:pairs:)`、`holdLine` | 沒有問題。 |
| #827 列車卡提早折返 | `Train.shortTurnCall`／`currentTrip`、`TrainCard`、GameCore `Deadlock.shortTurn` | **B4**（P3，延後）。 |
| #834 首日路線清單 | `LineReport.today`、`rowText` | 沒有問題：只用已結算的整點，不顯示暫時的損益；兩種語言一致。 |
| #844 決策 295 | 建議站點的分組、最近優先、已蓋的站排除、`pickPlatformPlace` | 沒有問題；文字與 VoiceOver 兩種語言一致。 |
| #851 決策 298，存檔 64 | 下面「二」 | 沒有問題。 |
| #869 | 台中捷運、桃園機捷、新北捷運的工具、JSON、`RealRidership`／`RealTransfers`、資料來源 | 沒有問題，見「三」。 |
| #872 | 只改文件（林鐵沒有分站運量） | 沒有問題。 |
| #850 `tdx-check.yml` | 整份 workflow | **B3**（P3，已修）；秘密不會進 log 或 artifact，fork 的 pull request 拿不到秘密，見「四」。 |

## 二、#851：存檔 63 → 64 與轉乘的平衡

- **缺 key**：`GameWorld` 沒有 `"realTransfers"` 就是關、`Station` 沒有 `"transferPoints"` 就是 0；寫出時只有開著才寫 `true`、只有大於 0 才寫點數，讀到 `"realTransfers": false`、關著卻有點數、點數超出 1–100、機廠有點數都拒絕。`SavedGame` 的遷移說明有 63 → 64 一步，`SaveFixtures/v64-real-transfers.json` 在。讀的順序：`isDepot` 先讀，才檢查點數。
- **指令**：`setTransfers(_:)` 先檢查全部再改，拒絕時世界不變；`setDepot` 改成機廠時點數歸零並重算需求；`setRealTransfers(false)` 全部歸零。關閉的站留著點數但 `transferTrips` 給 0（`landStations` 也排除關閉的站），與決策「關閉的車站沒有」一致。
- **Undo 與重播**：點數不是編輯，跟在編輯之後以 `.transfers` 記進指令紀錄；Undo 的快照在編輯之前取，含之前的點數，所以 Undo／Redo 拿回的世界和點數一致。重播的 `HeadlessGame` 沒有鐵路資料，照紀錄的值設定。
- **平衡**：點數照決策 298 的表（每天 1,000 人 1 點、四捨五入、至少 1；後備台鐵特等 14／一等 9／二等 2／其他 1、高鐵 20、捷運 3、輕軌與三鶯線與林鐵 1、高雄捷運檔在時環狀輕軌 1；各系統相加、最多 100），子 agent 也逐項對過 `transferPoints(of:data:ridership:)`。#869 讓台中、新北、桃園的部分站點數變了（高鐵臺中站 3 → 8 等），決策 298 的平衡表只量台鐵大站，沒有重量：**NOT ASSESSED — NO DATA**（`TRANSFER_REPORT=14` 的 `TransferReportTests`，要量時加台中捷運的站）。

## 三、#869 的資料

- `python3 -I tools/real-ridership/test_tools.py`：8 個測試通過、不用網路（VERIFIED）。
- 站名比對：子 agent 照 `RealRidership` 的 `stationKey` 寫探針，把 `track_stations.geojson` 每一站對到它系統的表：tmrt 18、tymc 22、ntdlrt 14、ntalrt 9、sanying 12、mrt 119、thsr 12 站全部對到，沒有對不到站的 key；krtc 只有環狀輕軌 37 站對不到，照設計給 1 點（哈瑪星與橘線同名，用橘線的數字）。
- 資料來源：三個新來源兩種語言都有，附資料集或網頁；台中捷運標政府資料開放授權第 1 版，新北捷運、桃園捷運照高鐵的做法標「公司公布的統計」。

## 四、發現

| 編號 | 發現 | 嚴重度 | 狀態 |
| --- | --- | --- | --- |
| B1 | 真實高架、隧道只比對構造物的「點」：一段很長的直線構造物中間描的短線不算在上面 | P2 | **已修** |
| B2 | 複線坡道上設月台，✓ 的價錢沒有算旁邊那條軌道的整平 | P2 | **已修** |
| B3 | `tdx-check.yml` 的 token 會跟著轉址送到別的主機 | P3 | **已修** |
| B4 | 已經誤點的車被提早折返，列車卡仍照舊的錯誤讀法 | P3 | **延後**（GameCore 的 `Deadlock.shortTurn`，A 組範圍） |

### B1：一段很長的直線高架或隧道，中間的短線不算在上面（#809）

- **位置**：`Sources/GamePresentation/RealRailStructures.swift` 的 `stretches(along:frame:system:)`，先用「構造物有沒有一個點在路徑的框內」篩選。
- **為什麼錯**：打包的 `rail_structures.json` 有 135 段點與點之間超過 1 km 的直線（高鐵橋 54、高鐵隧道 13、台鐵隧道 43、台鐵橋 25），最長 4.4 km（高鐵橋）與 6.5 km（高鐵隧道，只有兩個點）。網路工具沿真實鐵路描線（決策 279 第 3 步）時，兩次點擊都落在同一段裡，路徑的框內沒有構造物的點，整個構造物被跳過，描出來的軌道鋪在地面。後面每 16 m 取樣的比對本來會對到。示範地圖是整條線，不受影響。
- **重現**：`RealRailStructuresTests.testAPathWithinOneLongPieceOfAStructureIsOnIt`：0–8 km 的一座高鐵橋，路徑在 3–4 km。
- **預期**：一段 `.bridge`，約 0…1,000 m。**實際（`main`，VERIFIED）**：`[]`。
- **修法**：篩選改成「構造物任一段的框與路徑的框重疊」（只有一個點的照舊看點）。修後該類別與 `RealRailwayTracing`、`HighSpeedDemo`、`TRADemo`、`RealWorldDemo` 共 91 個測試通過（VERIFIED，3 個照設定跳過）。

### B2：複線坡道上的月台，✓ 少算旁邊軌道的整平（#818）

- **位置**：`Sources/GamePresentation/StationSiting.swift` 的 `networkPlatformCost`。`PlayerCommand.addPlatform` 在旁邊的軌道有坡度時先整平它（`beside.levelling`）再設月台、照付錢，但 ✓ 的價錢只算點的那條軌道的整平，違反決策 245「✓ 的價錢就是付的錢」。
- **重現**：`WholePriceTests.testADoubleTracksPlatformsOnAGradeSayTheirWholePrice`（同 `testANewStationsPlatformOnAGradeSaysItsWholePrice` 的坡地，鋪成複線）。
- **預期**：付的錢等於 ✓ 的價錢；錢不夠時說的價錢也是那個數。**實際（`main`，VERIFIED）**：✓ 說 $26.22，實際扣 $42.44；現金在兩者之間時 ✓ 沒有說不夠，按下才被拒絕，訊息的價錢與 ✓ 不同。
- **修法**：價錢加上旁邊軌道的整平，在 `pricingCopy()` 上蓋一次量出（蓋不起來的，✓ 也不設旁邊的月台，不加）。修後 `WholePriceTests`、`StationSitingTests`、`InsufficientFundsTests`、`NetworkBuildingSessionTests`、`FreeStationSessionTests`、`DoubleTrackPlatformTests`、`FeedbackSeventyThreeTests` 通過（VERIFIED）。
- **沒修的小地方**：地圖上的整平提示（`networkPlatformLevelling` 的文字）與成功訊息「整平了 N 公尺」仍只說點的那條軌道的長度與價錢（訊息的錢已經是兩條的合計）。要改得動提示的 memo 與兩種語言的文字，留給下一次動 `DoubleTrackPlatform` 的人。

### B3：TDX 的 token 跟著轉址送到別的主機（#850）

- **位置**：`.github/workflows/tdx-check.yml` 的 API 請求，`Authorization` 放在 `Request(headers:)`。Python 3.13 的 `HTTPRedirectHandler.redirect_request` 除了 `Content-Length`、`Content-Type` 以外照抄所有標頭，所以 TDX 若轉址（開放轉址或 CDN 搬家）到別的主機，token 也送過去；與檔案自己的註解「token 不送到別的主機」不符。只有 TDX 本身轉址才會發生、token 短效、不是 repository 的秘密，所以 P3。
- **重現**（探針只在本機跑，不進 repo）：本機開兩個 HTTP 伺服器，第一個 302 到第二個，第二個印出收到的 `Authorization`。照 workflow 的寫法收到 `Bearer SECRET`；改成 `add_unredirected_header` 收到 `None`（VERIFIED，Python 3.13.16）。
- **修法**：`Authorization` 改用 `add_unredirected_header`。抽出 heredoc 的腳本 `py_compile` 通過，沒有秘密時照舊印「Not set for this run」結束（VERIFIED）；真的連 TDX 要等這個 PR 的 `tdx-check.yml` run（UNVERIFIED LOCALLY）。
- **其餘檢查都沒問題**：沒有 `set -x`、`curl -v`，不印 token；秘密與輸入走 `env:`，不嵌進腳本；路徑限 `/api/basic|advanced/…` 且拒絕 `..`；只印「Token: received」、位元組數與 key 名；artifact 只有 API 的回答；觸發只有 `pull_request`（只這個檔）與 `workflow_dispatch`，沒有 `pull_request_target`，`permissions: contents: read`，不 checkout。fork 的 pull request 拿不到秘密；同一個 repository 的分支拿得到，那是 GitHub 對已有寫入權限的人的正常行為。

### B4：已經誤點的車被提早折返，列車卡照舊讀錯（#827，延後）

- **位置**：`DepartureBoard.swift` 的 `shortTurnCall(at:on:)` 只認得決策 288 改過的時刻（跳過的站與折回的站都等於折返的時刻）；但 `Deadlock.swift` 的 `shortTurn` 只在 `timetablePeriod == nil, early > 0` 時改時刻。車已經晚過它表定折回那一站的時間（`early <= 0`）就保留舊時刻，卡片回到 TestFlight 74.1 的錯：行程從沒到過的站算起、寫「已發車」、沒有「提早在 X 折返」。決策只寫了重複時刻表不認得，這一種沒寫。
- **重現（VERIFIED，但用構造的狀態）**：`ShortTurnCardTests` 的世界折返後，把時刻表換成 GameCore 在 `early <= 0` 時會留下的未移動時刻（整體提早 2 小時，所以是誤點），`shortTurnCall` 是 `nil`（預期 3），`currentTrip` 是 `2...4`（預期 `3...4`）。沒有用指令一路玩到「誤點又折返」；探針只在本機跑過，沒有加進測試 target，A 組修時照這個做法寫回歸測試。
- **為什麼延後**：修法在 GameCore 的 `Deadlock.shortTurn`（`early <= 0` 時也把跳過的站設成現在，其餘不移動），會動到行車的 golden 與 replay 要重驗，是 A 組（#823）的範圍；決策 302 的 session 也在 GameCore 調度附近。已交給 A 組。另一個做法是在決策 255 寫明這種情況不認得。

## 五、沒有算成發現的

- `TrackRise.bounds` 裡，長構造物中的車站高度仍拿構造物的上下限（註解說車站例外）：衝突那一步會拿掉，`HighSpeedDemo.rise` 也把車站高度設成相符，看不到錯。
- `networkDoubleChosen` 在一局內不重設：決策寫明。
- 中文狀態文字「照真實鐵路鋪成複線。」前面接了半形空白：只是排版。
- `networkPlatformBeside` 每畫面跑一次 `tracksMeet`（整個網路的搜尋）：沒有量到變慢，不算。
- #833 的 `.connect` 里程碑沒有軌道也算：GameCore 原有規則。

## 六、檢查

- `swift build --build-tests -Xswiftc -warnings-as-errors`：乾淨（VERIFIED）。
- B1、B2 的回歸測試：在 `main` 紅、修後綠（VERIFIED）；相關類別見上。
- `python3 -I tools/golden-checks/doc_numbers.py --check`：差異 0（VERIFIED）。
- 沒有動 campaign，不用跑 shard；GameCore 沒有改。完整的 GamePresentation 測試交給 CI（UNVERIFIED LOCALLY）；App 畫面、iOS build 交給 macOS CI。
