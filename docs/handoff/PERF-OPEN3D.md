# PERF-OPEN3D

- 派工單：PERF-OPEN3D（遊戲規劃第 63 任派；作者 2026-11-13 貼給 Mac 本機 session）。分支 `claude/perf-open3d`。
- session：Mac 本機（接實機 iPhone 17 Pro）。2026-11-13 壓縮過 1 次：不接新工作，再壓縮一次就停。
- 決策 [713](../decisions/713.md)。存檔版本、golden、fixture、GameCore：都不動。

## 做了什麼

- **B 段（決策 713）**：在模擬器上重現「每次開 3D 第一格停一秒」，找到原因（畫第一格時在主執行緒把 13 座機場重鋪一次，約 0.88 秒，其中 0.62 秒是每個機位重算每座登機橋），修了：登機橋端點每座機場只算一次、機場在背景鋪（`Map3DAircraft.Layer`）、區塊的頂點緩衝在背景上傳。模擬器同地點：第一格 CPU 最長 1,075 ms → 12 ms，格距最長 1,291 ms → 49 ms。細節、取樣數字、沒選的做法在決策 713。
- 新測試 `Map3DAircraftLayerTests`（4 個）；另有只在給 `PERF_SAVE` 時才跑的 `Map3DAircraftLayingReportTests`（量一份存檔鋪機場要多久）。

## 還留下什麼

寫這個檔時手機由另一個 session 在量 #2105（作者 11-13：「實機先等一下」），下面都還沒做：

- **B 段的實機數字**：main 與這個分支各錄一次開 3D 的 Time Profiler，補進決策 713 第 4 節。目標第一格 ≤ 100 ms。要確認 `makeUIView`（建立 Metal 畫面，模擬器 207 ms）在實機剩多少。
- **A 段**：#2098（PERF-FAR，決策 709）的實機驗收：「整個臺灣」存檔 3D 拉最遠的三角形、GPU 時間、fps（對照 main 的 267–277 萬、約 45 fps），遠、中、近各幾張圖，貼 #2098 並在 #1579 留「規劃請看」。MAP3D-CAP 合進 main 之後再量一次存檔 B 開 3D。
- **C 段（只量不改）**：存檔 B 開 600× 每 tick 花多久、花在哪、「tick 最多佔 60%」的限制佔多少；放涼後的 3D 最遠與 3D 600×；乾淨條件下過一次午夜（L19 P2-3）；示範模式鋪高鐵抽查；`FIX-L19-P3.md` 六項 UNVERIFIED 各看一眼。
- 下一張單 COACH-3D（決策 708）：這個 session 壓縮過，不接；請規劃另派。

## 這台 Mac 與手機上留下的東西（不在 repo）

- 手機存檔備份：`~/RailwayGameDeviceBackups/2026-11-13-before-perf-open3d/`（這個 session 開始前、還沒裝任何東西時的 `Application Support`）。
- 這個 session **沒有**在手機上裝過任何版本。
- 實機量法：`xcrun xctrace record --template 'Time Profiler' --device <udid> --attach RailwayGame` 可以用名字接上實機的行程（手機上有 `RailwayGameUITests-Runner` 在跑時名字會對到它，先關掉）；畫面用 `xcrun devicectl device capture screenshot`；數字用 `devicectl device copy from` 拿 `Diagnostics/frame-times.json`。

## UNVERIFIED

- 實機上的一切（見上）。模擬器的數字是 Mac 的 CPU，絕對值不能當實機的。
- 本機只跑了快的檢查（`swift build --build-tests -Xswiftc -warnings-as-errors`、`Map3DAircraftLayerTests`、`Map3DAirfieldsTests`、`FollowAircraftTests`、`ReviewL19FixTests`，模擬器的 Release 與 Debug 建置）；其餘交 CI。
- `Map3DAircraftLayingReportTests` 沒跑過（要 Release 的測試建置）。
- 跟著飛機時開 3D 不會被踢出跟隨：只讀過程式，沒有在畫面上試。
