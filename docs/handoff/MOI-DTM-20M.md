# MOI-DTM-20M：地面高度換成內政部 20 m DTM（決策 943）

session_01JMHz9Zbs6nGBXiRP1K9QQq，分支 `claude/moi-dtm-20m`。存檔版本、golden schema 不動。

## 進度

- 做到哪：量測完成並決定換（DTM＋保留 3 × 3 中位數）；`build_slope_grid.py` 加了第五個參數（DTM 的 `tw.tif`）、`compare_dems.py` 是量測工具；舊存檔的接縫 `HeightGridJoin.swift` 與 `HeightGridJoinTests` 已寫；資料來源已加內政部。正在重產 `taiwan_heights.dat`、`taiwan_water.json`，接著 `build_terrain.py`、改各測試釘住的數字。
- 已驗證：不給 DTM 時工具仍逐位元重現 main 的兩個檔。量測（1.875″ 格網）：台鐵地面段 1,268 km 超過 40‰ 的 100 m 段 3,032 → 1,893，高雄捷運 5 → 0；全島陡坡格 5,581,984 → 5,624,468（不留中位數會是 6,290,008）；台北車站 18 m → 6 m。
- 下一步的第一個指令：`python3 -I tools/real-world-population/build_slope_grid.py RailwayGameApp/Resources/RealWorld/taiwan_water.json <copernicus-dem/> RailwayGameApp/Resources/RealWorld/taiwan_water.json RailwayGameApp/Resources/RealWorld/taiwan_heights.dat <moi-dtm/tw.tif>`（約 8 分鐘），再 `swift build --build-tests -Xswiftc -warnings-as-errors`。
