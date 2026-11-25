# JAPAN-MAP-GROW 交接

作者（2026-11-24）：「我下一個地圖想往南開放日本地圖到熊本 順便開放九州新幹線」。五張主單與後續單的評分在
私有 repo `docs/priorities/JAPAN-KUMAMOTO.md`；這張是第一張「地圖能長大、舊存檔跟著長、南邊用買的」。

## 進度

- 做到哪：**GameCore 一半做完並合了（決策 969、存檔 113），畫面層一半還沒寫。** 沒有任何地圖包的範圍被改，
  玩家看不到變化。這一串壓縮兩次，照規則停（2026-11-25）。
- 已驗證（雲端 Linux，Swift 6.4.0）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`MapGrowthTests` 11、
  `MapExpansionTests` 27、`SavedGameTests` 38、`SaveVersionNotesTests` 1、`GoldenScenarioTests` 24、`ReplayFixtureTests` 3（1 跳過）、
  `MapPackExtentsTests` 4 全過。
- 下一步的第一個指令：`grep -rn "frame.anchor\|realWorld.anchor\|halfExtent" Sources/GamePresentation RailwayGameApp/Views`，
  照下面「畫面層 1」把「錨點在世界正中央」的假設一處一處改掉，先寫 `RealWorldFrame` 的測試。

## 作者定案的事（不要再問他怎麼設計）

作者說過「太難了」，不想被丟選項。直接照下面做，回報時用三、四句白話講「玩家會看到什麼」。

- 日本、香港、台灣的實景**新局都從 32 × 32 km（2 × 2 塊地圖塊）起跳**，其餘用買的，算成就。
- 香港與日本（福岡加熊本）另有**「整張全開」的選項，全開的不算成就與排行**，和「整個台灣」一樣。
- **芬蘭是冬季活動的地圖，維持整張開放，不改。**
- **已經在玩的存檔一律不收地、不鎖回去**：舊福岡存檔長大後擁有原本那四塊（蓋住原本的 17.6 × 22.2 km），南邊用買的，
  照舊算成就；舊香港存檔照舊整張開、照舊算成就。
- 先做日本（這張與後面四張），香港與台灣在 OVERSEAS-BUY-LAND。

## 做了什麼（決策 969）

- `Sources/GameCore/World/MapGrowth.swift`：`GameWorld.growMap(to:)`（西北角不動，往東往南長；重編 `.mapTile` 資產；
  被舊邊界切到的地塊從 `landBlocks`、地形、`roads.readBlocks` 拿掉，等畫面層重讀）、`mapGrowthProblem()`（存檔檢查）。
- `GameWorld.geoAnchorBounds`（錨點是哪一塊的正中央；`nil` = 整個世界）；`setGeoAnchor` 會清掉。
- `MapExpansion.granted`、`bought`；`enableMapExpansion(owning: [MapTile], townSeed:, ridersStep:)`；價錢與里程碑只算買的。
- `Terrain.forget(in:)`、`AssetRecord.owner` 與 `GameWorld.bounds` 改成 `internal(set)`。
- `SavedGame.currentVersion = 113`，`SaveFixtures/versions/113.md`、`SaveFixtures/v113-grown-map.json`
  （由 `MapGrowthTests` 在 `MAP_GROWTH_SAVE_NEW=1` 時產生一次；之後不可再產生）。
- `MapPack.extents(ofManifest:)`：`pack.json` 的 `earlier`（以前的範圍，由舊到新，每個是下一個的西北部分）。

## 還留下什麼：畫面層（這張單的另一半）

設計已經想好，還沒寫：

1. **實景座標框。** `RealWorldFrame.init?(world:)` 改成 `self.init(anchor: anchor, bounds: world.geoAnchorBounds ?? world.bounds)`
   （`Sources/GamePresentation/RealWorldMap.swift`）。投影（`middleX/Y`）這樣就對了；`Map3DBaseMap`、`Map3DLowRise`、`Map3DFootprints`、
   `RealRoadCells`、`Map3DSharedBuild` 用的都是投影，不用改。要改的是把「錨點 ≈ 世界中央」當搜尋半徑用的地方：
   `RealRailwayYield.swift:90-91`（`lines(near: frame.anchor, within: …)`）、`RailwayGameApp/Views/MapView.swift:3850`、
   `OSMMapBackground.swift:61-74`、`AppleMapBackground.swift:152-158,206`、`RealTrainMotion.swift:517-524`（用 `halfExtent` 從錨點加減，
   改成從世界四邊加邊距）。建議加 `RealWorldFrame.place(atMiddleOf: WorldRegion) -> GeoAnchor`（區域中央就是 `middleX/Y` 時
   回傳原本的 `anchor`，一位不差；否則用 `coordinate(worldX:worldY:)`），上面幾處改用它。
2. **地圖包的鋪法。** 有 `earlier` 的包：錨點 = `earlier[0].anchor`，`earlier[0].bounds` = `geoAnchorBounds`，世界的大小 =
   每個階段的東南角在 `earlier[0]` 的座標框裡的世界座標（無條件進位）。**沒有 `earlier` 的包，錨點與大小要和今天一位不差**
   （香港、羅瓦涅米、福岡各寫一個測試釘住現在的數字）。`OverseasPlace.holds`、`OverseasGround.holds` 改成：現在的圖
   （`geoAnchor`、`bounds`、`geoAnchorBounds` 都相同）或任何一個以前的階段。
3. **讀到舊存檔就長大。** `GameLauncher.begin`（`awaitedCity` 檢查之後、建立 `GameSession` 之前）：世界停在以前的階段、
   而裝置上的包已經是新範圍時，在複本上 `growMap(to:)`，`mapExpansion == nil` 就
   `enableMapExpansion(owning: 蓋住 earlier[0].bounds 的所有塊（福岡是 2 × 2）, townSeed: nil, ridersStep: …)`。
   `ridersStep` 用 `RealWorldExpansion.ridersStep(forResidents:)`，餵那幾塊在包的 `population.json` 裡的居民數。
   裝置上的包還是舊的（決策 858 §1.8）就不長，照舊玩。
4. **新局走同一條路。** `newOverseasGame` 遇到有 `earlier` 的包：先照 `earlier[0]` 開局，再走 3 的同一個函式。
   新局與舊存檔因此擁有同樣的四塊。
5. **按鈕與成就。** `MapExpansionSession.swift:88-91` 的 `namesMapExpansionButton` 改成 `owned.count <= granted`；
   `Achievements.swift:96` 的 `tilesBought` 改成 `world.mapExpansion?.bought ?? 0`。
6. **測試（GamePresentation，Linux）。** 三個包的錨點與大小一位不差；一個合成的「長大的包」讓舊範圍的世界長大後
   每一站、每一段軌道的經緯度不變（差 0），擁有四塊，第一塊的價錢與里程碑和一塊起跳的新局一樣。

做完後：`python3 -I tools/golden-checks/doc_numbers.py --check`，`swift build --build-tests -Xswiftc -warnings-as-errors`，
GamePresentation 的相關測試；決策 969 補「後來」一段。畫面沒有新的，不用截圖（還沒有任何包變大）。

## 要小心的

- **颱風**照 `bounds` 抽（`Weather.typhoons(ofYear:in:)`），長大後當年的颱風會重抽。沒有改；要不要改成照 `geoAnchorBounds`
  抽，KUMAMOTO-OPEN 時決定（改了會動 golden 嗎：先量）。
- **已讀的地面塊**不重讀：舊邊界那一排的地面高度，邊界外的部分是後來才有的。軌道高度是照地面量的，所以不敢動；
  KUMAMOTO-GROUND 做包時在福岡舊南緣（33.52N）與東緣（130.48E）各看一次有沒有階差。
- **祭典、活動場地等目錄**在長大後是不是還對得到（多半照經緯度，應該不受影響，沒驗）。
- **海外地圖上「買真實路線自動買沿線的地」**（決策 401）與「待售路線離你的地多遠」（`RealLineListing`）只在台灣跑過，
  日本開賣前要在福岡跑一次。
- 開局四塊要讀四塊的地，開局時間要量（KUMAMOTO-OPEN）。
- `pack.json` 之後可能要一個「開局擁有的範圍」的欄位（香港、台灣要指定 2 × 2 放哪）；日本不用，就是蓋住 `earlier[0]` 的那幾塊。

## 熊本的數字（後面的單用）

- 新範圍：北 33.72、西 130.29 不變；南 **32.69**、東 **130.90**。約 56.5 × 114.1 km，4 × 7 塊。
- 開局的 2 × 2 塊（從西北角）到約 130.64E、33.42N：太宰府在內，快到鳥栖。
- `WorldBounds.maximumSide = 1 << 25`（524 km），夠。

## 後面的單（評分檔有分數與五方）

1 JAPAN-MAP-GROW（這張，剩畫面層）∥ 2 KYUSHU-SHINKANSEN-DATA ∥ 3 KUMAMOTO-GROUND → 4 SHINKANSEN-SALE → 5 KUMAMOTO-OPEN，
之後 KYUSHU-SHINKANSEN-TRAINS、KUMAMOTO-TRAM、KUMAMOTO-LANDMARKS、NISHITETSU-OMUTA、JR-KAGOSHIMA-LINE、OVERSEAS-BUY-LAND。
1 的畫面層與 4 動 GamePresentation；只有 1 的前半（已合）動 GameCore。
