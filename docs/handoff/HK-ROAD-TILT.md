# HK-ROAD-TILT：道路橫向找平（路床）

派工單 HK-ROAD-TILT（bug，2.60，`a91453/railway-assets-private-2` `docs/priorities/HK-ROADS.md` 第 1 項），工作串「修香港山坡道路左右傾斜」，分支 `claude/project-thread-lw0f37`，決策 865。只改 GamePresentation；GameCore、存檔版本、golden、replay 都不動。原 session 在第二次壓縮後照規定停手，**PR 留 draft，還不能合**。

## 進度

- 做到哪：路床（`Map3DRoadBed.swift`）寫完並接到路面、人行道、中線、標線、街具、車流、橋與匝道的高度、國道縱斷面；決策 865、對照圖、新測試都在分支上。**還沒做：把多出來的三角形降下來**（下面第 1 項），所以 PR 是 draft。
- 已驗證（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`Map3DRoadBedTests` 5 個通過；相關既有測試的結果寫在 PR。真實地形量測（預覽工具，不是實機）：路面左右高差 p95 香港薄扶林 3.29 → 0.00 m、台北 0.13 → 0.00 m、羅瓦涅米 0.38 → 0.00 m；三角形香港 +55%、台北 +22%、羅瓦涅米 +56%。
- 下一步的第一個指令：照專案檔案區 `handoff/HK-ROAD-TILT-measure.patch` 開頭的說明把量測補丁放回去（不提交），`swift build --build-tests`，再跑裡面的 `measure2.sh tpe taipei` 當基準，然後動下面第 1 項。

## 做了什麼

決策 865 寫了規則、沒選的做法、量測、五方與參考對照。一句話：地面不動，每條底圖的路沿線每 2 m 取「橫向最高的地面」當床高，路面兩側同高，路口互相撐到同高再降回，並行的路併成一個平台，低側立擋牆。平地的路高度不變。所有地圖共用（`addBaseMap`）。

對照圖：`docs/art/hk-road-tilt-2026-11-18/overview.jpg`。

## 還留下什麼（照順序）

1. **三角形多兩成到五成，合併前要降下來。** 來源與方向：
   - 路面、人行道、中線、標線在路床每個轉折多切一刀（`bedCuts`，1 cm 的 `bends`，和決策 391 共用）。路床的折點在「路中心±半寬」過 64 m 網格線與對角線的地方，一格大約 6 個，折點不落在 2 m 的取樣點上時前後兩點都算轉折，所以一個折點切兩刀。原本一格只切 3 刀（`splits`）。
   - 可以試的：(a) 路床自己先簡化成折線（只留偏離超過幾公分的點，而且不低於原值），`bedCuts` 只切折線的頂點；(b) 整段都在床上的路面不再併 `splits` 的網格切點（床上的路不需要跟著地面的三角形）；(c) 擋牆的站點放寬（現在牆頂、牆腳各 1 cm），`Map3DRoadBed.wall` 0.35 m 在羅瓦涅米立了一萬六千個三角形的矮牆，可以提高門檻或只在落差大於人行道高度很多時才立；(d) 側傾很小的地圖（台北 p95 0.13 m）幾乎沒有得到什麼，卻付了兩成，可以考慮床高與中心地面差不到某個值的路不切。
   - 目標自己定，建議：台北 +5% 以內、香港與羅瓦涅米 +20% 以內，再量一次實機或 `Map3DFrameCostReportTests`。
2. **看圖**：香港薄扶林的圓環低側牆很高（路面 68.1 m，路緣下地面 57–60 m）。寬路的床取到上坡側人行道外緣，路口再把相接的路撐到同高（最多 9 m，`tallest`）。要不要改成床高取路中心附近（半挖半填，上坡側切進地面一點）是設計題，動之前先拍圖。
3. 縱坡沒變好、略差（香港 secondary p95 16.1% → 17.9%）。評分在私有庫 `docs/priorities/HK-ROAD-TILT.md`。
4. 台北、羅瓦涅米只量了數字，沒拍改前改後的圖；海邊的路（派工單寫「山坡與海邊」）沒有單獨拍。
5. 沒做的小項（決策 865「沒做、沒驗證」）：公司自己的公車路與種子街道沒有路床、斷頭路端面沒牆、`Map3DRoadTunnels` 洞口與 `bridgeDecks` 內部仍讀 `drawnGround`、高低差超過 2 m 的並行路各走各的。
6. **實機（Metal）沒看過。**

## 量測怎麼重跑

補丁與三個腳本在專案檔案區 `handoff/HK-ROAD-TILT-measure.patch`（不在 repo 裡）。重點：

- 預覽工具的世界若沒有買線，`GameWorld.groundHeight` 整張圖回答 0，場景是平的；補丁在蓋場景前呼叫 `world.mapGround()`（App 的 `GameLauncher` 也這樣做），高度檔才會被讀到。這個該正式加進 `tools/map3d-preview/Map3DPreviewDump.swift.txt`（這次沒加）。
- `MAP3D_TILT=1` 印出各級道路左右高差與縱坡的百分位、三角形數；`MAP3D_NO_BED=1`（三行暫時的開關）是「改前」。
- 香港：`MAP3D_WORLD=hongkong MAP3D_AT=22.2715:114.1290 MAP3D_REAL=1 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 MAP3D_DAY=1 MAP3D_MINUTE=600`，鏡頭 `a:-1110:-326:170:30:62:62;b:180:472:170:120:85:62;wide:-400:-400:900:20:50:50`。

## UNVERIFIED

- 實機與 Metal：沒有。
- 完整測試：只跑了相關的類別，其餘交給 CI。
- macOS／Xcode 建置：交給 CI。
