# 公測前抓蟲：公車與車輛（派工單 BH4，2026-10-30）

遊戲規劃第 32 任派，分支 `claude/bughunt-vehicles`，main `9fb305d` 起。範圍：買賣公車、公車路線（建立、改站、刪除、班距、單行道、隧道、真實公車路線）、2D／3D 公車行駛與停站、跟公車的視角、公車收支與載客；列車買車選型與節數、編組、3D 編組順序與外觀、3D 跟車與駕駛室視角在換車／換線／刪車／進機廠時、車庫展示。

## 1. 怎麼玩的

Linux 上用測試的方式照玩家的順序操作（腳本放 scratchpad，沒有進 repo）：

- GameCore（`BusRouteTests` 的世界：兩站一線一車、一條路、幾格住宅）：開一條接駁線與一條市區公車（市區線的第一站在 A 站 400 m 內，接到 A），跑一天；接駁線賣到 0 台車再跑一天；市區線拿掉接 A 的那個站牌、再改站；收購市區線後關掉它；再開一條只有兩個班次的市區線、拆掉 A 站；每一步都存檔讀回（`WorldInvariants.roundTripProblem`），最後讀回再跑一天。
- GamePresentation（`BusRouteEditorTests` 的世界）：開線後用公車工具編輯它、編輯中拆掉它的車站；編輯中按「復原」把那條線的開通復原掉；0 台車的線再編輯、加站牌。
- 3D：`Map3DBuses.lay` 給一條鋪不上地面的回程。
- 跑了既有的 `BusRouteTests`、`CityBusTripsTests`、`BusMotionTests`、`Map3DBusLayerTests`、`Map3DBusesTests`、`BusRouteEditorTests`、`CityBusToolTests`、`BusOwnRoadsTests`、`Map3DFollowTests`、`Map3DFollowViewsTests`、`Map3DCabTests`、`Map3DShowcaseTests`、`RollingStockSessionTests`、`RollingStockCatalogTests`：全綠（Linux，VERIFIED）。
- 讀了 10/25 之後改過的公車路網（決策 474 單行道與隧道、476 續篇玩家的路進路網、438 市區公車）、3D 跟車（`Map3DFollow`、`Map3DMetalView.follow`）、車庫（決策 492）、賣車與跟車（`GameSession.followedTrain`、`endFollowIfGone`）。

GameCore 的公車規則（0 台車、刪站牌、刪車站、收購後關線、存讀檔）在上面的順序裡都對：錢、載客、存檔讀回都沒有錯。跟車的列車被賣、離開軌道、整條線被刪時，`followedTrain` 變成 `nil`，3D 鏡頭飛回地圖自己的視角，沒有卡住。車庫的列並空時有預設鏡頭。

## 2. P1（已修，同一個 PR）

**P1-1 3D 地圖的公車回程鋪不上時當掉。** `Map3DBuses.lay`（`Sources/GamePresentation/Map3DBuses.swift`）：決策 474 讓回程自己找路；回程在場景裡鋪不上（附近沒有車道、或太短）時退回用去程，但回程站牌的位置仍用回程自己的點的編號去查去程的點，回程的點比去程多時 `Index out of range`，3D 地圖當掉；比較少時站牌停錯地方。

- 會紅的測試：`Map3DBusesTests.testAWayBackThatCannotBeLaidIsTheWayOutWithItsStops`（在舊程式上 `Fatal error: Index out of range`，修好後綠）。
- 修法：回程鋪不上時，它的站牌也用去程的。
- 沒有在真實地圖上重現：要回程整條離 3D 車道 150 m 以上、或在車站 40 m 內被剪到不到 1 m 才會發生，靠構造的回程觸發。實機 UNVERIFIED。

## 3. P2

沒有找到。

## 4. P3

**P3-1 復原掉正在編輯的公車路線，編輯還留著。** 用公車工具編輯一條線（`editBusRoute`）時按「復原」把那條線的開通復原掉：草稿仍指著那條線，預覽寫「那條公車路線已不存在」，不能確認；「拿掉上一個站牌」拿到最後也清不掉（`removeLastBusStop` 在編輯時不放掉車站）。換工具就好。
- 重現：`BusRouteEditorTests` 的世界，點 A、點 (8, 26)、確認；`editBusRoute(1)`；`undo()`；`busPreview?.problem` 是 "That bus route no longer exists."。
- 建議修法：`dropSelectionOfMissing()` 裡，`busDraft.route` 指的線不在了就 `clearBusDraft()`（拆站已經會清，因為拆站要先換工具）。GamePresentation 一行與一個測試。
- 玩家：少見，但看到一句錯誤卡著不知道怎麼辦；鐵道迷：無；開發：一行；美術：無；音樂：無。

**P3-2 減少公車不退錢，訊息也沒說。** 路線卡把公車從 3 台減到 1 台，GameCore 照規則「少的不賣錢」（`setBusCount`），訊息只寫「現在跑 1 輛車。」。買一台 $50,000，玩家會以為錢算錯。
- 建議修法：減少時訊息加一句「減少的公車不退錢」（兩種語言），或照列車的賣車規則退帳面價值的一部分（那要動 GameCore，公測後再議）。
- 玩家：會以為少算了錢；鐵道迷：無；開發：只改訊息最小；美術：無；音樂：無。

**P3-3 沒有實景底圖時，鋪了捷徑路後 2D 的公車線還畫舊路。** `busMapOverlay` 的 `busPathMemo` 只比站牌、車站和底圖路網，不比玩家的道路格子；空白地圖上鋪一條更近的路之後，2D 還畫原來的路，3D 的公車走新的最短路，GameCore 的路程（車資、時間、成本）還是開線時的。看程式得出，沒有跑。
- 建議修法：memo 多記 `world.roads` 的格子數或一個版本號；路程要跟著變則是 GameCore 的事（改站時才重算），公測後再議。
- 玩家：2D 和 3D 不一樣會困惑；鐵道迷：無；開發：小；美術：路線和車對不上；音樂：無。

## 5. 範圍裡還沒有的功能（不是 bug，列給規劃）

- **跟著公車的視角**：沒有。跟車（`followedTrainID`、`Map3DFollow`）只接受列車。
- **2D 地圖上行駛的公車**：沒有，2D 只畫路線與站牌；會動的公車只在 3D（決策 400 的 10i-6 只做了 3D）。
- **收購真實公車路線**（10i-4）：GameCore 有 `recordBusAcquisition`，App 沒有用到；`RealBusAcquisition.swift` 沒有做。HANDOFF 已記在待做。
- **混編**：GameCore 一列車只有一種車型（`Train.type`），沒有每節不同的車型；3D 的編組順序照車型的配方。

## 6. 驗證

- Linux：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；第 1 節列的測試類與 `Map3DBusesTests` 新測試綠。VERIFIED。
- iOS Simulator、實機（3D 公車在真實地圖上、跟車鏡頭）：UNVERIFIED。
- 參考庫與外部專案：這輪是抓蟲，沒有新功能要移植；修法是這個專案自己的。
