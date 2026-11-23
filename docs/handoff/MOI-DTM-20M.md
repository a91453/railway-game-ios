# MOI-DTM-20M：地面高度換成內政部 20 m DTM（決策 943）

session_01JMHz9Zbs6nGBXiRP1K9QQq，分支 `claude/moi-dtm-20m`。**這個 session 在第二次壓縮後依規定停手，工作沒做完，PR 是草稿，不能合。** 存檔版本、golden schema 不動；決策 943 由這條分支保留。

## 1. 已做完（VERIFIED，Linux，Swift 6.4）

- 資料：內政部地政司 **2026 年版** 全臺灣 20 m DTM（data.gov.tw 資料集 178729，政府資料開放授權條款第 1 版），讀自 `a91453/railway-reference-private` 提交 `ca0a5f2` 的 `Railway/moi-dtm-2026/data/`（台灣三片 uint16 GeoTIFF，金門另一片 EPSG:3825；高度 = v/10 − 100，無資料 65535，格點為點）。工具只讀參考庫的檔，不下載；原檔不進這個倉庫。
- 涵蓋：本島、蘭嶼、小琉球、金門。澎湖、馬祖、綠島與苗栗山區一小塊（約 5 萬格）仍用 Copernicus，接縫以差值擴散接平。陸地格 11,643,630，其中 11,533,107（99.05 %）來自 DTM。
- 工具：`tools/real-world-population/build_slope_grid.py`（`MOI_SHEETS`、`moi_sheets`、`tm2`、`mean3`、`moi_at`、`moi_on_grid`、`with_moi`，第五個參數是 DTM 資料夾；不給時逐位元重現 main 的兩個檔）。
- 三個檔已重產：`taiwan_water.json` 1,981,803 bytes（陡坡 17,163.1 km²，main 17,059.3）；`taiwan_heights.dat` 11,587,858 bytes（−9 到 3,909 m）；`taiwan_terrain.pmtiles` 115 片 9,734,258 bytes。
- 舊存檔：`Sources/GamePresentation/HeightGridJoin.swift`（新讀的地塊在邊上接到存檔裡已有的地塊，`GameSession.heights` 的 didSet 補一圈），`HeightGridJoinTests` 5 項過。存檔版本不動。
- 示範地圖：DTM 的地比較平順，高度擬合要的節點變少、邊變長，三貂嶺分岔旁的長邊會晃進支線而 `trackConflict`。`TrackPlan` 加 `closeLongestEdge`（預設不變），`RealWorldDemoGround` 在分岔旁用 100 m。`RealWorldDemoGroundTests` 5 項過。
- 資料來源：`DataSourceCredits` 加「台灣的地形」（2026 年版、資料集 178729），Copernicus 一則改成只講澎湖、馬祖、綠島與苗栗山區一小塊。
- 這次跑過且通過：`swift build --build-tests -Xswiftc -warnings-as-errors`；`HeightGridJoinTests`、`WaterGridTests`、`HeightGridTests`、`RealWorldDemoGroundTests`、`RealRailwaysTests`、`TrainHornTests`、`DataSourceCredit*`（共 51 項）。

## 2. 量測與結論（細表在 #2118 留言「MOI-DTM-20M 64m/32m 量測」）

台鐵地面段 1,268.5 km，100 m 窗超過 40‰ 的段數（直接讀檔／64 m 地塊角點，也就是遊戲實際用的／32 m 角點）：

| 高度來源 | 直接 | 64 m 角點 | 32 m 角點 |
|---|---|---|---|
| Copernicus 1.875″（main） | 3,032 | 2,810 | 2,943 |
| DTM 1.875″＋3×3 中位數（**採用**） | 1,603 | **1,622** | 1,579 |
| DTM 1.875″ 不留中位數 | 1,676 | 1,810 | 1,663 |
| DTM 1″ | 1,212 | 1,942 | 1,342 |
| DTM 直接 20 m | 944 | 2,321 | 1,311 |

- 遊戲的地面是 GameCore 的 64 m 地塊角點（`HeightGrid.ground(of:frame:)` 每個角點讀檔一次），TrackRise 與 3D 地面讀角點，不讀檔。所以在 64 m 角點下，1″ 與 20 m 反而比 1.875″＋中位數差（取樣到細碎起伏）。**結論：這張票維持 1.875″＋中位數，不做 1″**（1″ 檔 38,991,870 bytes，是現在的 3.4 倍）。協調 session 曾說「高度格照 1″」，我已在 #2118 回報這組數字，沒有收到回覆；要 1″ 得先把地面改成 32 m。
- 3×3 中位數留著：64 m 角點下拿掉會從 1,622 變 1,810。
- 下一步候選「32 m 地面」：1″ 在 32 m 角點是 1,342（比現在的 1,622 少 17 %）。代價：每 km² 地塊三角形 512 → 2,048；`GroundBlock` 289 → 1,089 個 Int16，要升存檔版本；`Map3DScene` 的 64 m 格網、道路、標線、橋約 18 處要改。尚未評分。

## 3. 還沒做完（接手的人照這個順序）

現在的工作樹用的是 2026 資料。以下四個測試在新資料上是紅的，**不可以為了變綠改期望值**，每個都要先查原因：

1. `Map3DLevelledGroundTests.testCentralTaipeiIsLevelled`：原始粗糙度 0.138，測試要求 > 0.2。這是對資料的前提（「台北原本不平，所以要整平」），DTM 本來就平。先在舊資料上量出舊值，再決定是降門檻（寫理由）還是整平規則已不需要。
2. `Map3DStationExteriorsTests.testEachStandsWhereOpenStreetMapHasIt`：`taichungHSR` 近景 8,910 個三角形，預算 8,000（舊資料 7,979，留下比例 0.856 → 0.902：軌道淨空切掉的比較少）。其他站差不到 100。要決定是預算還是切法。
3. `RealRailwayTracingTests.testAStationOnARealViaductMidTraceCanBeBuilt`：唭哩岸的島式月台預覽回「月台兩端外的軌道不夠長，放不下轉轍器」。尚未診斷。
4. `TrackGeometryProblemTests.testATraceNoGradeReachesShowsItsWay`：南澳那一段（站 −3,700 到 −3,500 m）現在鋪得過去（沒有問題、高度差 0）。要找另一段真的沒有坡度可達的，或說明理由後改寫。

另外：

5. **整套 GamePresentation 測試還沒在 2026 資料上跑過**（先前那次是 2024 版）。還要跑 `SharedStationLayoutTests`、`RealLineAcquisitionTests|RealLineRebuildTests|LiujiaLineTrainsTests|RealLineBoughtAgainTests`、`TimetableCheckupTests`、`TimetableCheckupTaiwanTests`、`Map3DOpenEveryStartTests`、`RealWorldDataLoadTests`。
6. `WaitingPreviewTests.testTheNetworkPreviewsTakeLittleStackWhileTheScreenAsks` 在本機 `--parallel` 下會紅（60,256 ≥ 49,152），把我的改動還原也紅，單獨跑是綠的（42 KB）：不是這張票造成的，CI 上 UNVERIFIED。
7. `WaterGridTests` 已改的陡坡格數（main → 2026）：台北 2,959/2,784 → 2,677/2,500；基隆 7,628/3,295 → 7,182/2,958；高雄 786/785 → 734/734；阿里山 51,912/4,079 → 52,388/4,147；馬公 20/6 不變（仍是 Copernicus）。PR 要逐一說明：都是資料來源換了，規則沒變。
8. 文件還是舊的，要改：`docs/decisions/943.md`（現在寫的是 2024 版、Mapterhorn 鏡像；要改成 2026 版、參考庫提交、新量測表、為何不做 1″／20 m／32 m、示範地圖的 `closeLongestEdge`、五個角度）；`tools/real-world-population/README.md`（第 61 行起）；`build_slope_grid.py` 的模組說明（第五個參數）；`tools/basemap/README.md` 第 30 行的片數與大小；`tools/real-world-population/compare_dems.py` 還在用舊介面（`moi_on_grid(data, moi_path)`、`tw.tif`），**現在跑不動**，要改成 `list(slopes.moi_sheets(folder))`、`moi_on_grid(data, sheets, True)`，並加上 64 m／32 m 角點的沿線量測。
9. 協調 session 要的量測還沒做：`RowMemo` 列數與記憶體、`ground(of:frame:)` 在台北與平溪一個 3D 畫面的時間、整島峰值記憶體；買下的線 TrackRise 的段數、坡度變化、橋／隧道／路堤件數與 3D 三角形前後比；「沿線太陡」拒絕次數前後比。
10. 前後對照的 3D 預覽（`tools/map3d-preview`，JPEG 品質約 85）：台北、高雄地下段、平溪、內灣。
11. `python3 -I tools/golden-checks/doc_numbers.py --check`；PR 補對照表（參考庫 `Railway/moi-dtm-2026/` 的檔與 `DATA_USE_NOTICES.json` → `build_slope_grid.py` 的 `MOI_SHEETS`／`moi_sheets` 與 `DataSourceCredits`）、外部專案搜尋說明（沒有用到；TM2 投影與 Coons 補片是自己寫的）、五個角度。
12. 分支落後 `main` 約 61 個提交，合併前要併 `main`。合併後在 #2118 留言並回報合併 SHA。

## 4. 重產的指令

```sh
# main 的 taiwan_water.json（輸入的水域）與 Copernicus 圖磚要先備好；DTM 在參考庫
python3 -I tools/real-world-population/build_slope_grid.py <main 的 taiwan_water.json> <copernicus-dem/> \
  RailwayGameApp/Resources/RealWorld/taiwan_water.json RailwayGameApp/Resources/RealWorld/taiwan_heights.dat \
  <railway-reference-private>/Railway/moi-dtm-2026/data      # 約 4.6 分鐘
python3 -I tools/basemap/build_terrain.py RailwayGameApp/Resources/RealWorld/taiwan_heights.dat \
  RailwayGameApp/Resources/BaseMap/taiwan_terrain.pmtiles
```

要在舊資料上比對一個測試：把 `main` 的 `taiwan_heights.dat`、`taiwan_water.json` 暫時放回 `RailwayGameApp/Resources/RealWorld/`（`git show origin/main:<path>`），跑完再 `git checkout` 回來。這個 session 的暫存資料夾（Copernicus 圖磚、量測腳本 `measure2.py`、npy 快取）隨容器消失，量測腳本的做法已寫在上面第 8 點要補進 `compare_dems.py`。

## 5. 對 A2 GHOST-LINES 的影響

- 新讀的地塊高度變了（台北車站一帶約 18 m → 6 m，山谷整體平順），而舊存檔裡已讀過的地塊保持原樣，交界由 `HeightGrid.joined` 接平。舊存檔裡買下的線仍在舊地面上，不會因為換檔而浮空或埋進地裡；但**新買或重鋪**的線會落在新地面上，同一條線在兩種地面上節點數不同（DTM 上節點較少、邊較長）。A2 若用「軌道與地面的高度差」判斷幽靈線，要注意舊存檔裡地塊邊界那一圈是補過的。
- 示範地圖重建後節點位置變了（三貂嶺後 +81/+162/+243 m 的節點變成 +138/+276；深澳 0/126/253 變成 0/253），A2 若有釘示範地圖邊號的測試要重看。
