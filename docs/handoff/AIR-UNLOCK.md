# AIR-UNLOCK

派工單 AIR-UNLOCK（session_01YGNNuo5GgdCSuPmFia67cc，`claude/air-unlock`，2026-11-12；遊戲規劃第 63 任派，#1579 留言 6835486993）。決策 712。不動 GameCore、存檔版本（93 已釋出）、golden、ReplayFixtures、SaveFixtures。這個 session 壓縮過一次，照規矩只做完第一個 PR；**第二、三個 PR 沒做，規劃說另派 AIR-UNLOCK-2 接**，接著寫這個檔。

## 做完的：PR 1，香港的大地圖（開關關著）

細節在 `docs/decisions/712.md`。地圖包多了 `extent`（62.6 × 45.5 km）與 `population.json`（WorldPop 香港 2025，739.7 萬人）；`OverseasGround`、`GameWorld.newOverseasGame`、`GameLauncher.startOverseasMap` 開香港的世界，土地隨車站讀入。`OverseasMaps.open` 仍是空的，App 沒有任何不同。地圖不用切塊（量測在決策裡）。

## 做完的：PR 2，開航規則與畫面（開關仍關）

AIR-UNLOCK-2（session_01YGNNupFY6Z2K8uhkAqFeJF，`claude/air-unlock-2`，2026-11-13；遊戲規劃第 64 任派，#1579 留言 6841699809）。細節在 `docs/decisions/712.md`「續：第二個 PR」。不動 GameCore、存檔、golden、三套 fixture。

- 規則在 `Sources/GamePresentation/AirRoutes.swift`；記在 `LauncherPreferences.airRoutesOpened`；`GameLauncher.checkAirRoutes(of:)` 在午夜、開局／讀檔、資料讀完時查。
- 選地圖多一列、機場那一列多一行、開航的狀態列與新聞；香港國際機場在 `AirportCatalog.overseasPlaces`。
- 下面「PR 2」的 1–6 都做了。第 6 點（量 500 人）的數字在決策裡。
- 截圖：`WebsiteScreenshotTests.testAirRouteUnlock`，用 Debug 啟動參數 `-open-overseas`（開關關著也讀香港）與 `-screenshot-air-routes offered|opened`。

## 還留下的

### PR 2：開航規則與畫面（**已做**，見上；原本的清單留著對照）

1. 條件：飛香港的機場（桃園一、二航廈、臺中、高雄、花蓮）`yesterdayRiders` ≥ 500，午夜結算後開航；在 GamePresentation 讀，不動 GameCore。示範模式直接開放。
2. 記在 `LauncherPreferences`（例如 `airRoutesOpened`）；`GameSession` 每天結算後與讀檔時檢查，成立就記下並在那一局提示（狀態訊息＋新聞）。重裝會掉，規劃接受。
3. 選地圖畫面（`RailwayGameApp/Views/RealWorldPicker.swift`，「全台灣」那一列約 445–470 行）下面加一列大地圖「香港」：鎖著時寫怎麼開航，開了就 `launcher.startOverseasMap(.hongKong)`。現有 16 km 的「香港」地點照舊不鎖。**第三級截圖**：這一列與開航提示，規劃看過才合。先讀 ui-review、motion 兩個 skill。
4. 台灣機場面板多一行「昨天 N／500 人」（只有有香港航點的機場）。
5. 香港國際機場進 `AirportCatalog`（`withAirports` 現在只認台灣的 `tourism` 世界，香港的世界要另開一條路），航點臺北桃園、高雄、臺中、花蓮用決策 700 的民航局年報數字；機場全年旅客與架次要查香港機管局／民航處的公開統計，查不到標 UNVERIFIED。
6. 500 人還沒量（economy-balance：NOT ASSESSED）：用 `AirportReportTests` 量機場捷運、高雄紅線與一條自己鋪的小線，數字寫回決策 712。（量了機場捷運：每航廈一天約 1 萬人，HEALTHY；高雄紅線不在收購清單上，量不了；自己鋪的線報告裡列車不跑，NOT ASSESSED。見決策 712「500 人量到的」。）

### PR 3：打開

`OverseasMaps.open` 加 `.hongKong`（`testNoGroundIsReadWhileNoCityIsOpen` 要跟著改）、網站 `credits.html`（`docs/HANDOFF.md` §4.64；`DataSourceCredits` 的香港兩筆已在）、What's New、`tools/hk-map/README.md` 第 5 行「遊戲還不讀這一包」。

**已做**（`claude/air-unlock-3`，疊在 PR 2 上；決策 712「續二」）：開關打開、機場的資料來源一筆、官網 `credits.html`（私庫 #136，draft，作者合，等發版後）、`WhatsNew` 129 一行與 What to Test、`tools/hk-map/README.md`；測試的載入改成讀和 App 一樣的資料（台灣加香港）。香港地圖的 2D、3D 截圖：`WebsiteScreenshotTests/testHongKongMap`（示範模式從選地圖那一列進去）。

沒做完、接手的人要知道的：

- 荃灣綫示範鋪線少中環、金鐘：沒查到原因（不用 GameCore）。
- 自己鋪的機場線一天載多少人沒有量到（報告裡用指令鋪的線沒有軌道、列車不跑）；500 人只在「買機場捷運」這條路上量過。
- 要 GameCore 的兩項（東涌綫尖峰末班、香港的假日與幣值）列在決策 712「續二」，給規劃排。

### 停手時的狀態（2026-11-13，AIR-UNLOCK-2 第 2 次壓縮後交接）

- PR 2 = #2111（`claude/air-unlock-2`，head `d1aeb3cb157db94895634a14fcc3a34f6b956be7`）與 PR 3 = #2115（`claude/air-unlock-3`，疊在 #2111 上）都是 draft，CI 全綠（Swift gate、Xcode build、release archive）。**都還沒轉 ready**，因為截圖驗收沒過（下面兩項）。
- 截圖：`website-screenshots.yml` run 43369272845（分支 `claude/air-unlock-3`，`testAirRouteUnlock testHongKongMap`），artifact `website-screenshots`。看過的結果：
  - 過：`air-route-picker-closed`（香港一列，鎖頭與怎麼開航）、`air-route-picker-open`（飛機圖示與地圖說明）、`air-route-opened-notice`（狀態列「台灣↔香港開航了…」）、`hong-kong-map-2d`（港鐵各綫暗色、機場圖示、資料來源一行）。
  - **沒拍到**：`air-route-airport-open`、`air-route-airport-progress` 兩張都停在「觀光景點」清單最上面的「老街」，機場那一列在畫面外。`openAirports(in:)` 的 `row.swipeUp()` 沒有把清單捲上來（測試照樣過）。要改成像選地圖那樣一步步拖到 `tourism.airport.1` 整列在畫面內再拍。機場列上的進度句子（`AirportDay.airRouteText`）因此還沒有人在畫面上看過，只有 Linux 測試。
  - **不能交**：`hong-kong-map-3d` 整張是灰的，只有按鈕和操作提示，25 fps，沒有地面、軌道、車站。原因沒查。可能的方向：香港沒有水域／高度／建物資料時 3D 場景的地面沒畫；或鏡頭開在地圖外；遊戲時間 22:25 是夜間。這是打開香港（PR 3）前要修的，照 model-look／ui-review 要看圖。
- 所以建議：#2111（開關關著）在機場列截圖補上後可以先合；#2115 等 3D 地圖畫得出東西再合。兩張 PR 的說明都寫了這個狀態。
- 沒拍的：小 iPhone、iPad、淺色、最大字級。
- 私庫官網 `credits.html`：`a91453/railway-reference-private` #136（draft），發版後由作者合；沒在瀏覽器看過。

### AIR-UNLOCK-3 接手後（2026-11-13，session_01YGNNuo2hA5L2KmEkZy3WWj）

- **工作登記 #1579 滿 2,500 則，GitHub 不再收留言**（403）；這個 session 的登記與回報都貼不上去，也無法 `send_message` 給規劃（不同頻道）。回報寫在兩張 PR 的留言裡。要規劃開「工作登記（四）」。
- #2111：機場那一列沒拍到是 `row.swipeUp()` 一下滑過頭（機場那一段跑到畫面上方，停在第一個景點「老街」）。`openAirports(in:english:)` 改成一小步一小步拖到「寫著香港的那一列機場」整列在畫面內，不在就讓測試紅。重拍的 run 與結果見 #2111 的留言。
- #2115：3D 是空的原因與修法在決策 712「續三」：3D 的地面全讀底圖圖磚，App 只有台灣的；地圖包現在自帶 `basemap.pmtiles`（`tools/hk-map/build_hk_basemap.py`），3D 的地面、土地的真實道路與 2D 地圖都讀它。Linux 的 `HongKongBaseMapTests` 與 WebGL 預覽（`docs/art/hong-kong-3d-ground-2026-11-13/overview.png`）看過；模擬器的截圖見 #2115 的留言。
- `testHongKongMap` 現在先按示範模式的「鋪好這一帶的真實路線」再開 3D，拍遠、中、近三張。
- 還沒有的（決策 712「續三」列了）：香港的建物足跡、高度、規則用的水域、地名網格。官網 `credits.html`（私庫 #136）要加「香港的地圖」一筆（`hongKongMap`）。

- **工作登記換成 #2118**（#1579 滿了）；這個 session 在那裡登記、回報。壓縮 1 次（留言在 #2118）。
- **#2111 已合併**（2026-11-13）。機場那一列的截圖：run 43379720213（`testAirRouteUnlock`，綠）。中間紅過一次（run 43376989911）是測試自己的上緣界線太嚴（64 點，列在 45 點），改成 36 點。
- **#2115 的截圖**（`testHongKongMap`）：run 43384020296 的 3D 已經有道路、綠地、水，但沒有軌道：示範鋪線一次只鋪 40 公里以內的畫面，整張香港約 100 公里寬，被擋下。測試改成先放大兩次再鋪、3D 每次拉近 1.8 倍。run **43388165195**（head `d49c332e`，綠）：2D 鋪出葵涌、荃灣、九龍一帶的車站與綫；3D 遠、中、近三張都有海、道路與路燈、綠地、水塘、軌道（深色的線，高架）。拍的時間是遊戲裡的凌晨 3–4 點，畫面偏暗；街區沒有建物（續三列的下一步）。
- **Release archive 常跑到 30 分鐘上限被取消**（`release-archive.yml` 的 `timeout-minutes: 30`；今天成功時 19–28 分鐘，#2111、#2115 各兩次被取消，早上 run 645–647 也是）。不是必要檢查；要不要放寬請規劃決定，這個 session 沒有動 workflow。
- 剩下的：#2115 等規劃看截圖（第 3 級）才轉 ready。

### AIR-UNLOCK-4（2026-11-13，session_01YGNNum1wxGSp5Gc2z6SXn4；第 1 次壓縮後做完手上這張）

做了（決策 712「續四」，同一個分支 `claude/air-unlock-3`、PR #2115）：

- 香港的建物：`buildings.pmtiles`（117,245 棟，2.26 MB），3D 地圖讀得到。
- 開航改成照航線、兩邊對稱：新玩家選第一張地圖（香港可以），另一張靠飛過去的機場一天 500 人打開；舊玩家視為從台灣開始。清單每一列寫開或鎖、從哪裡、目前最多的一天。
- `testHongKongMap` 改成白天、跟著停在九龍站的機場快綫列車；`testAirRouteUnlock` 多了兩個方向的清單。
- 新消息與 TestFlight 說明的香港那一條放在 130。

接手的人先看：

- 截圖 run 與規劃的驗收結果在 #2118 與 PR #2115 的留言；沒過的畫面從那裡接。
- 沒做、留給下一輪：香港的地形與水域網格；香港國際機場的跑道與航廈模型；國際金融中心一帶因為車站與軌道清建物而空著（`clearOf` 的現有規則）；機場快綫在香港站一帶畫成地面的綠帶；港鐵共用軌道與東涌綫少發班次（GameCore）；六條密集的綫沒有班次；玩家買飛機。
- 網站資料來源頁（私有倉庫的 credits）要補「香港的建物」。
- 重做建物：`tools/hk-map/README.md` 第 7 步。

### 香港地圖本身還有的毛病（重現方法都是 `swift test --skip-build --filter HongKongMapTests`）

- **機場快綫與東涌綫只能買一條**（共用 28 km 的軌道）；已擁有一條時另一條馬上拒絕並說明。真正的做法在決策 712。
- **先買迪士尼綫再買東涌綫被拒**（軌道太近）；反過來可以。沒有測試釘住，重現：在 `testEveryLineOnSaleIsBought` 的做法裡照這個順序買。
- **東涌綫尖峰每個方向最後一班沒發**（4／282）：行車管制一列車佔一個站間，欣澳–東涌 7 分鐘對 6 分鐘的班距。是 GameCore 的規則，沒動；`testTheTungChungLineRunsOnTheMap` 釘在至多 4 班。其他五條綫沒跑過兩天的檢查。
- **示範鋪線的荃灣綫少中環、金鐘**（從尖沙咀鋪起），沒查。
- **六條密集的綫**（荃灣、港島、觀塘、將軍澳、屯馬、東鐵）沒有 `metro_runs`，不在出售清單（決策 697）。
- **離峰班距只有一個早上的取樣**（決策 697），照派工單沒有重抓。
- 香港沒有水域、高度、地名網格：海是陸地的顏色，全平。osmtoday 有 `asia/china/hong_kong.pbf`（約 44 MB），`tools/real-world-population/build_water_grid.py` 可以照搬。
- GameCore 的假日與幣值是台灣的；香港的世界照用。

## UNVERIFIED

- Xcode 建置、UI 測試（交 CI）。
- 62 km 的地圖在 2D／3D 地圖上的畫面與幀率（Linux 量不到，開關打開後要在 Mac／實機看）。
- ASSET-PACK（Background Assets）沒碰；這裡每個檔都經 `MapPack(root:)` 讀。
