# PERF-3D-DRAW：3D 繪製與建置成本

派工單 PERF-3D-DRAW（#2118 登記），雲端工作串「優化 3D 繪製效能」，分支 `claude/project-thread-emio31`，決策 876。
存檔版本、golden schema、GameCore 都不動。這串壓縮兩次後照規則停手，下面「還留下什麼」交給下一串。

## 進度

- 做完的：邊走邊建的區塊不再把整個路網、整份時刻表重算一次（`Map3DSharedBuild`，決策 876）；量測用的報告測試 `Map3DMapLoadReportTests`。
- 已驗證（Linux，Swift 6.4）：改前改後五張圖 40 個指紋相同（基準 `ce5129b`）；台北一個區塊 2.6–2.9 → 0.40–0.76 s（本機 debug `-O`）；`Map3DSharedBuildTests` 與碰到的既有類別通過（清單在 PR）。**實機沒跑過。**
- 下一步的第一個指令（接手時先量現況）：`MAP3D_LOAD_MAP=fukuoka MAP3D_LOAD_BUY=all swift test -c release -Xswiftc -enable-testing --filter Map3DMapLoadReportTests`

## 怎麼量

`Tests/GamePresentationTests/Map3DMapLoadReportTests.swift`，只在給了 `MAP3D_LOAD_MAP` 時跑，印出的每行以 `MAP3D-LOAD` 開頭：
場景建置時間與最慢的步驟、各層三角形、緩衝區（數量、位元組、最後一頁沒用到的）、鏡頭 120 m 到 12,000 m 每一幀的
draw call 與三角形（照 `Map3DMetalView.draw` 的分法）、場景指紋，以及四種串流區塊（鏡頭下一個、東邊 2 km 一個、
東邊 3 km 與北邊 3 km 的 5 × 5）各建兩次的時間、指紋與最慢的八個步驟。

```sh
# 地圖：taiwan、hongkong、rovaniemi、fukuoka，或 save（MAP3D_LOAD_SAVE 指到存檔；作者的存檔在私有庫，不進這個 repo）
MAP3D_LOAD_MAP=taiwan MAP3D_LOAD_BUY=all 'MAP3D_LOAD_AT=Taipei:25.0478:121.5170;Miaoli:24.5701:120.8224' \
    swift test -c release -Xswiftc -enable-testing --filter Map3DMapLoadReportTests
```

- release 從頭建要 35 分鐘、只改測試也要 11 分鐘。來回試的時候，本機把 `Package.swift` 的 GamePresentation 也加 `-O`
  （`.when(platforms: [.iOS, .linux])`，**不要 commit**），debug 增量重建約 3.5 分鐘；那個設定的秒數只能看相對值
  （台灣的區塊比 release 慢約 2.5 倍）。
- **指紋相同就是畫面沒變**：改建置器而不想改畫面的 PR，改前改後各跑一次、比 `digest` 那幾行。同一份程式 release 與 debug `-O` 的指紋也相同。
- 手機大約是這台機器單核時間的 1.5–2 倍（`docs/handoff/PERF-DEVICE-2026-11-14.md` 的比例）。

## 這次量到、還沒動的（評分在私有庫 `docs/priorities/PERF-3D-DRAW.md`）

1. **地下車站的整網計算（PERF-3D-UNDERGROUND-MEMO）**：`Map3DUndergroundStations(snapshot, point:, cover:)`（`lay`、`boxes`、`openings`）
   每個區塊都從整個路網算一次，和區塊在哪無關。福岡（82 座地下月台）一個區塊的「track cover」步驟 0.277 s，佔 76 %；
   香港的區塊這次幾乎沒變快也是它。放進 `Map3DSharedBuild`（鑰匙：路網指紋加場景原點），做法和這次的 `samples` 一樣，
   用指紋證明沒變。這是下一個最划算的。
2. **道路橋與隧道、土地覆蓋與水每個區塊的固定成本（PERF-3D-BLOCK-FIXED）**：各約 0.09 s 與 0.05 s，還有建物輪廓與
   `Map3DLowRise` 讀圖磚；`PMTilesArchive.tile(zoom:x:y:)` 每讀一片都把根目錄與葉目錄重新解壓、重新解析。
3. **每個區塊的 draw call（PERF-3D-DRAWS）**：遠景 8–12 km 一幀 575–1,440 次（每個區塊底圖、遠景、方盒、影子各一次）；
   近景 44–277 次，多半是小物件（每個區塊每種模型一次）。一個場景 3,000–4,800 個緩衝區，最後一頁沒用到的共 29–40 MB；
   場景佔 120–418 MB，其中有 CPU 端留著的網格副本。**這些要在實機量每幀時間才知道值不值得**（11-14 的重存檔：CPU 中位數 21.8 ms、GPU 7.9 ms，
   2.65–2.76 GB 並有記憶體警告）。
4. **整個場景第一次建置（PERF-3D-FIRST-BUILD）**：台北全買 18 s，最大的是道路橋與隧道 3.2 s、建物輪廓 2.7 s、道路 2.2 s。
5. **決策 861 的步調模擬**假設一個區塊 0.069 s、5 × 5 區塊 0.242 s，實際是十倍上下；用量到的時間重跑，看提前量與一次建幾塊要不要改。
6. **改後的 release 數字沒量**，實機（Metal）沒跑過：下一版 TestFlight 請作者在買了很多線的存檔上移動鏡頭，看新的地方補出來有沒有變快、有沒有東西不見。

## 加新的整圖計算時

建置器裡只要有「每個區塊都從整個路網／整份真實資料／整個世界算一次、結果和區塊在哪無關」的東西，放進
`Map3DSharedBuild`：用算出它的輸入當鑰匙（`Map3DTrackSamples.mark`、`RealKey`、`WorldKey`），鑰匙不合就照原樣自己算；
要先篩掉遠處的，用同一批逐點結果算的包圍盒（才是精確的，不是近似）。它在兩條建置執行緒上被同時讀，內容要是值、進出都在鎖裡。
