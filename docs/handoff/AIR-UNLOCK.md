# AIR-UNLOCK

派工單 AIR-UNLOCK（session_01YGNNuo5GgdCSuPmFia67cc，`claude/air-unlock`，2026-11-12；遊戲規劃第 63 任派，#1579 留言 6835486993）。決策 712。不動 GameCore、存檔版本（93 已釋出）、golden、ReplayFixtures、SaveFixtures。這個 session 壓縮過一次，照規矩只做完第一個 PR；**第二、三個 PR 沒做，規劃說另派 AIR-UNLOCK-2 接**，接著寫這個檔。

## 做完的：PR 1，香港的大地圖（開關關著）

細節在 `docs/decisions/712.md`。地圖包多了 `extent`（62.6 × 45.5 km）與 `population.json`（WorldPop 香港 2025，739.7 萬人）；`OverseasGround`、`GameWorld.newOverseasGame`、`GameLauncher.startOverseasMap` 開香港的世界，土地隨車站讀入。`OverseasMaps.open` 仍是空的，App 沒有任何不同。地圖不用切塊（量測在決策裡）。

## 還留下的

### PR 2：開航規則與畫面（規劃 2026-11-12 回覆定案，四題都照設計 #1579 留言 6835572366）

1. 條件：飛香港的機場（桃園一、二航廈、臺中、高雄、花蓮）`yesterdayRiders` ≥ 500，午夜結算後開航；在 GamePresentation 讀，不動 GameCore。示範模式直接開放。
2. 記在 `LauncherPreferences`（例如 `airRoutesOpened`）；`GameSession` 每天結算後與讀檔時檢查，成立就記下並在那一局提示（狀態訊息＋新聞）。重裝會掉，規劃接受。
3. 選地圖畫面（`RailwayGameApp/Views/RealWorldPicker.swift`，「全台灣」那一列約 445–470 行）下面加一列大地圖「香港」：鎖著時寫怎麼開航，開了就 `launcher.startOverseasMap(.hongKong)`。現有 16 km 的「香港」地點照舊不鎖。**第三級截圖**：這一列與開航提示，規劃看過才合。先讀 ui-review、motion 兩個 skill。
4. 台灣機場面板多一行「昨天 N／500 人」（只有有香港航點的機場）。
5. 香港國際機場進 `AirportCatalog`（`withAirports` 現在只認台灣的 `tourism` 世界，香港的世界要另開一條路），航點臺北桃園、高雄、臺中、花蓮用決策 700 的民航局年報數字；機場全年旅客與架次要查香港機管局／民航處的公開統計，查不到標 UNVERIFIED。
6. 500 人還沒量（economy-balance：NOT ASSESSED）：用 `AirportReportTests` 量機場捷運、高雄紅線與一條自己鋪的小線，數字寫回決策 712。

### PR 3：打開

`OverseasMaps.open` 加 `.hongKong`（`testNoGroundIsReadWhileNoCityIsOpen` 要跟著改）、網站 `credits.html`（`docs/HANDOFF.md` §4.64；`DataSourceCredits` 的香港兩筆已在）、What's New、`tools/hk-map/README.md` 第 5 行「遊戲還不讀這一包」。

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
