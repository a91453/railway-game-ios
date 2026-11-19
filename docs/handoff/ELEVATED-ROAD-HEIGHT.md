# ELEVATED-ROAD-HEIGHT（決策 391「後來（ELEVATED-ROAD-HEIGHT）」）

- 派工：協調者（私有庫 `docs/priorities/ELEVATED-ROADS.md` 第 1 項，2.70）。工作串「抬高高架道路到 9 公尺」，分支 `claude/project-thread-pb7y0l`。
- 只改 GamePresentation（`Map3DRoadBridge.swift`、`Map3DBaseMap.swift` 的讀取範圍、資料來源那一行字）與 `Map3DRoadBridgeTests`、`RoadLookRealTests`；存檔、golden、GameCore、決策號都不動。

## 進度

- 做到哪：做完，PR 已開。
- 已驗證：本機 `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；道路相關 9 個測試類別全過；五個交流道與文湖線、青馬的量測在決策 391「後來（ELEVATED-ROAD-HEIGHT）」。
- PR 第一次 CI 紅在 `Map3DSceneMemoryTests.testTheDemosInterchangesMeetAtOneHeightOrAStoreyApart`（決策 607 的窄縫門檻，本機原本沒跑到這個類別）：213 → 232 處，門檻 215 → 235，理由與兩類新增的地方寫在決策 391 這則後來的「量」與「測試」。同一次 CI 還紅在 `Map3DInterchangeStreetTests`（台中交流道 600 m 內的行道樹 300 → 288，少的 12 棵對過位置，11 棵在同一條引道變長的街上），門檻 300 → 288。這兩個類別之後動道路橋高度都要跑。
- 下一步的第一個指令：沒有（留下的項目見下）。

## 狀態

1. 高架道路第一層 9 m、之後每層加 6 m（9、15、21、27、33），`Map3DRoadBridges.rise(ofLevel:)`，各地圖共用。
2. 橋尾在橋內先降回 3 m（`endDips(into:ends:others:)`），接出去的引道從原本的高度開始、落在原本的地方；橋下的路上方與兩側 10 m 保持全高。
3. `longestRamp` 360 → 420 m、`Map3DBaseMap.bridgeReach` 450 → 510 m（第三層 21 m 以 5% 下到地面的長度，各自保留原本的餘裕）。

## 留給之後的（評分在私有庫 `docs/priorities/ELEVATED-ROADS.md`）

- ROAD-OVER-LOW-VIADUCT：高樓層的道路橋遇到買下的鐵路高架，整座被壓到梁下（市民大道高架在文湖線下，改前 20.4 → 3.6 m，改後 23.4 → 3.6 m）。這是原本就有的規則（「斜交的橋從高架下面過」，`testARoadBridgeAlongAViaductRidesOverIt` 釘著），這張沒改，只是多壓 3 m。
- RAMP-SIDE-STREETS：從高架側邊（不是橋尾）接出去的平面道路，引道比以前長最多 60 m，橋尾下坡救不到；五個交流道地面引道合計多一成上下，碰到引道的巷道多 6%–77%（高雄中正 31 → 55）。
- 短的跨線橋（橋下的路離橋尾不到 60 m 的降不滿、不到 10 m 的不降），引道最多一樣多 60 m：併在 RAMP-SIDE-STREETS 一起看。
- bug LINK-DECK-DIP（2.10）：匝道的橋在橋內先降的那一段還貼著它離開的主線橋，兩片同層的橋面差 0.8–2.7 m（示範場景 10 處）。要改的是 `endDips` 裡往回碰到別的橋側邊的那個分支（`left = max(left, rest.drop)`）：留一段不降的距離；匝道短的時候橋尾降不滿 3 m、引道變長，要一起量。修掉之後把 `Map3DInterchangeTests.swift` 的 235 往下調。
- 看窄縫門檻每一處：`ROADIX_ALL=1 swift test --skip-build --filter "Map3DSceneMemoryTests/testTheDemosInterchangesMeetAtOneHeightOrAStoreyApart"`（每處一行 `ALL 差 類別 x z 緯度, 經度 兩條路`），單看一處用 `ROADIX_AT=x,z` 跑 `testROADIXLookAtOneSite`。改前的清單同樣把三個數字設回 6、360、450 跑一次。
- ELEVATED-ROAD-PARAPET-LAMPS（原有，2.35）：護牆上的路燈，沒做。
- 實機（Metal）沒看過；只有 Linux 的量測與 WebGL 預覽。高雄沒有買線量過道路橋鑽鐵路高架（台北文湖線、香港東涌綫各量一處）。

## 量測探針

沒有提交。做法同 `docs/handoff/ROAD-LAYER-HEIGHT.md`：`tools/map3d-preview/Map3DPreviewDump.swift.txt` 複製到測試目錄後加一段，用 `MAP3D_WORLD=island`（`MAP3D_AT` 台北 25.0478:121.5170、高雄 22.6394:120.3024，`MAP3D_FOCUS` 五個交流道的原點）蓋整個場景，量：路面顏色的三角形每 2 m 一格的疊板（上下差 0.5–4.5 m 與 4.5–7 m）、同一座甲板裡以 20° 以上交叉的每一對橋在交點的高度差、地面道路被抬高 0.5 m 以上的長度、端點落在引道上而自己在地面的巷道數、道路橋在鐵路高架下被壓低的量。改前的數字用同一份程式把第一層設回 6 m、`longestRamp` 360、`bridgeReach` 450 量（等於 main）。注意：場景會讀到範圍外 `bridgeReach` 內的橋，買了線的大場景兩種設定讀到的橋數不同（文湖線場景 617 對 715 段），長度與巷道數不能直接比，只比同一批橋的地方。
