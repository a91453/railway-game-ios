# MOI-DTM-20M：地面高度換成內政部 20 m DTM（決策 943）

分支 `claude/moi-dtm-20m`，PR #2621。開頭是 session_01JMHz9Zbs6nGBXiRP1K9QQq（第二次壓縮後停手），接手的是 session_01JMHz9YMth81xa2qy8KK3J4。存檔版本、golden schema 不動；決策 943 由這條分支保留。145 已發（協調者 11-23），這張單不進 145。

## 1. 做了什麼

- 地面高度、陡坡格、底圖山影改用內政部 2026 年版全臺灣 20 m DTM（data.gov.tw 178729，政府資料開放授權條款第 1 版），讀自 `a91453/railway-reference-private` `ca0a5f2` 的 `Railway/moi-dtm-2026/data/`。陸地格 99.05 % 來自 DTM；澎湖、馬祖、綠島與苗栗山區一小塊仍是 Copernicus。格網維持 1.875″＋3×3 中位數。
- 舊存檔：`HeightGridJoin.swift`，新讀的地塊在邊上接到存檔已有的地塊；存檔版本不動（協調者決定）。
- 新地面碰到的規則與期望值，全部寫在決策 943 §5、§6：
  - 唭哩岸的水平段多留 8 m。
  - 台中高鐵整個在軌道淨空上方的屋頂骨架不再切塊，三角形 8,910 → 7,028。
  - 示範地圖分岔旁的長邊 100 m。
  - 南澳、台北整平、文湖線引道、苗栗塹、交流道的期望值。
- 工具：`build_slope_grid.py` 第五個參數；`compare_dems.py` 比兩版打包的檔，約 8 秒。

## 2. 量測（細表在決策 943）

- 台鐵地面段 1,268.5 km，100 m 窗超過 40‰ 的段數，在遊戲讀的 64 m 角點上：2,806 → 1,597（−43 %）。
- 買下真實路線（`TimetableCheckupAllBoughtTests.wholeTaiwan`，每條單獨買）：15 條在兩種地面上都買得到，沒有一條被拒（沒有 `trackConflict`）。有坡度的邊大多變少，例如文湖線 409 → 345、桃園機捷 682 → 597、高雄環狀線 222 → 161。
- 纜車：貓空的纜索最低離地 0.93 m（129 個取樣低於 3 m）→ 3.0 m（1 個）；日月潭 4.98 → 3.98 m。塔腳都貼地。
- 地標：12 個的腳都跟著地面走。拉魯島照舊（湖面 747 m，腳 746.5 m）。慈恩塔在山頂，腳 943 → 933 m。美麗華摩天輪的腳在屋頂 33.4 m，地面 17 → 6 m。
- 讀高度：`HeightGrid` 載入 12–14 ms；100 個地塊的 `ground(of:frame:)`，台北 320 → 418 ms、平溪 327 → 283 ms（同一台 Linux，一次量，誤差大）。

## 3. 還沒做完

- **`HighSpeedDemoTests.testWithCurveLimitsTheSetsKeepToTheRealDayAsWell` 是紅的，沒有放寬。** 已在 #2118 回報，等手動 ci.yml 的整天時刻表檢查與 main 比過再決定。
  - 新地面讓示範線的曲線較緩，三段從「不開限速」變成「開限速也趕得上」，所以照決策 217 保留限速。
  - 五站車 27 在站 2 附近因此變慢。第 10 列出站被擋約 1 分鐘（決策 228），照決策 306 補不回來，比關限速晚 120 s。第 15 列同理，晚 180 s 對 66 s。
  - 我的打算：整天檢查沒變差，就把容許值 1 → 3 分鐘並寫理由；變差就停手等決定。
  - 在 c9061ac 上 PR 的 selected-6 只紅這一個測試（第 10 列 120 s > 60 s、第 15 列 180 s > 126 s），其他全綠；已在 PR 留言。
- **接手的人照這個順序做**（session_01JMHz9YMth81xa2qy8KK3J4 第二次壓縮後停手）：
  1. 手動 ci.yml run 45164555622（分支 c9061ac）跑完後，讀五個 `timetable-checkup` job 的 `TIMETABLE_CHECKUP` 行，四項（沒發車、誤點、出庫誤點、尖峰間隔）和 main 的夜間 run 45079414440 逐條線比，寫成表放進 PR。
  2. 沒有變差：放寬 `HighSpeedDemoTests.swift` 約 560 行的容許值（1 → 3 分鐘），寫出理由（決策 217/228/306，上面兩段），並在決策 943 §6 加一條。明顯變差：在 #2118 回報，停手等協調者決定，不要自己放寬。
  3. 加 `full-ci` 標籤，重跑 PR 的 run；同時最多 2 個改 GameCore 的 PR 跑 CI。
  4. 跑一次 `website-screenshots.yml`（分支 `claude/moi-dtm-20m`），失敗不重跑。
  5. 補 PR 說明：對照表（`Railway/moi-dtm-2026/data/` → `build_slope_grid.py` 的 `MOI_SHEETS`／`moi_sheets`、`DataSourceCredits`）、外部搜尋（沒有用到）、五個角度、所有變動的數字（決策 943 §5–§6）、§2 的量測。
  6. CI 綠了就合併（合併前若 main 有動先併 main），然後在 #2118 回報；協調者接著派 TERRAIN-CHECK-A。
- 合併後協調者另派 TERRAIN-CHECK-A，在新地面上看場景（橋、平交道、車站、地標、纜車），不是這張單的事。
- 「已讀但空的地塊改讀新高度」另案評分。

## 4. 重產的指令

```sh
python3 -I tools/real-world-population/build_slope_grid.py <main 的 taiwan_water.json> <copernicus-dem/> \
  RailwayGameApp/Resources/RealWorld/taiwan_water.json RailwayGameApp/Resources/RealWorld/taiwan_heights.dat \
  <railway-reference-private>/Railway/moi-dtm-2026/data      # 約 4.6 分鐘
python3 -I tools/basemap/build_terrain.py RailwayGameApp/Resources/RealWorld/taiwan_heights.dat \
  RailwayGameApp/Resources/BaseMap/taiwan_terrain.pmtiles
```

要在舊資料上比一個測試：把 `main` 的 `taiwan_heights.dat`、`taiwan_water.json` 暫時放回 `RailwayGameApp/Resources/RealWorld/`（`git show origin/main:<path>`），跑完再 `git checkout` 回來。

## 5. 對 A2 GHOST-LINES 的影響

- 新讀的地塊高度變了（台北車站一帶約 18 m → 6 m），舊存檔已讀過的地塊保持原樣，交界由 `HeightGrid.joined` 接平。舊存檔裡買下的線仍在舊地面上；新買或重鋪的線落在新地面上，節點較少、邊較長。
- 示範地圖重建後節點位置變了（三貂嶺後 +81/+162/+243 m → +138/+276；深澳 0/126/253 → 0/253），釘示範地圖邊號的測試要重看。
