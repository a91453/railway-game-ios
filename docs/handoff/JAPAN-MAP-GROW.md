# JAPAN-MAP-GROW 交接

作者（2026-11-24）：「我下一個地圖想往南開放日本地圖到熊本 順便開放九州新幹線」。五張主單與後續單的評分在
私有 repo `docs/priorities/JAPAN-KUMAMOTO.md`；這張是第一張「地圖能長大、舊存檔跟著長、南邊用買的」。

## 進度

- 做到哪：**這張單做完了（2026-11-25）。** GameCore 一半在 #2666（決策 969、存檔 113），畫面層一半在分支
  `claude/project-thread-e6erls` 的 PR（決策 969「後來」一段）。三個包都還沒有 `earlier`，玩家看不到變化；
  福岡的 `pack.json` 寫上熊本的範圍與 `earlier`（KUMAMOTO-GROUND）之後，舊存檔開起來就會長大、新局四塊起跳。
- 已驗證（雲端 Linux，Swift 6.4.0）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`MapGrowthLayoutTests` 8
  與 `MapExpansionSessionTests`、`AchievementsTests`、`FukuokaRailwaysTests`、`HongKongMapTests`、`RovaniemiRailwaysTests`、
  `RealRailwayYieldTests`、`RealTrainMotionTests`、`AmbientRealTrainsTests`、`RealWorldMapTests`、`RealWorldExpansionTests`、
  `MapPackDownloadsTests`、`AirRoutesTests`、`RealWorldLoadingTests`、`MapPackExtentsTests` 全過（189 個，1 跳過）。
- 下一張接這裡的是 KUMAMOTO-GROUND（寫 `earlier`）與 KUMAMOTO-OPEN（見下面「還留下什麼」）。

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

## 畫面層做了什麼（決策 969「後來」）

- `RealWorldFrame.init?(world:)` 用 `geoAnchorBounds ?? bounds`；`RealWorldFrame.place(atMiddleOf:)`。
  `RealRailwayYield`、`MapView` 的樣式選單、`AppleMapBackground`、`OSMMapBackground` 改從世界或地圖的中央找真實鐵道；
  `RealTrainTraffic(operations:frame:bounds:)` 從世界四邊加邊距。
- `MapPack.Layout`（`OverseasMaps.swift`）：錨點、現在的世界、以前每個階段的世界、`anchorBounds`、`startTiles`、`holds`。
  `OverseasGround`、`OverseasPlace` 的 `anchor`、`bounds` 改成從 `layout` 讀。
- `OverseasGround.grown(_:)`：舊階段的世界長大、擁有 `startTiles`；`GameLauncher.begin` 在 `awaitedCity` 檢查後呼叫它。
  `GameWorld.newOverseasGame` 有 `earlier` 時先照第一個範圍開局再 `grown`。
- `namesMapExpansionButton` 看 `MapExpansion.bought == 0`；`AchievementFacts.tilesBought` 用 `bought`。
- 測試 `Tests/GamePresentationTests/MapGrowthLayoutTests.swift`。

## 還留下什麼（KUMAMOTO-OPEN 的事）

- **「整張全開、不計成就」的選項**還沒做（評分檔第 5 張）。`newOverseasGame` 遇到有 `earlier` 的包一律四塊起跳。
- **裝置上的包比存檔舊**：已經長大的存檔（`bounds` 是新範圍），裝置上卻是還沒長大的舊包時，`OverseasGround.holds`
  認不得它，`overseasAwaited` 也沒有它（包在裝置上），會被當成台灣的地面。正常更新不會發生（存檔要先在新包上
  長大），但換機、還原舊版時可能；KUMAMOTO-OPEN 時看包的更新方式要不要擋。
- 讀到舊存檔長大的那一次，預先讀好的路（`RoadsReadAhead`）因為世界大小變了不會被用，會重讀一次；開檔會慢一點，量一次。

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
