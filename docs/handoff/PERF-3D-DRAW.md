# PERF-3D-DRAW：3D 繪製與建置成本

派工單 PERF-3D-DRAW（#2118 登記），雲端工作串「優化 3D 繪製效能」，分支 `claude/project-thread-emio31`，決策 876。
存檔版本、golden schema、GameCore 都不動。這串壓縮兩次後照規則停手，下面「還留下什麼」交給下一串。

## 進度

- 做完的：邊走邊建的區塊不再把整個路網、整份時刻表重算一次（`Map3DSharedBuild`，決策 876）；量測用的報告測試 `Map3DMapLoadReportTests`；地下車站也進了備忘（決策 876「後來」，第二串）。
- 已驗證（Linux，Swift 6.4）：改前改後五張圖 40 個指紋相同（基準 `ce5129b`）；台北一個區塊 2.6–2.9 → 0.40–0.76 s（本機 debug `-O`）；`Map3DSharedBuildTests` 與碰到的既有類別通過（清單在 PR）。**實機沒跑過。**
- 下一步的第一個指令（接手時先量現況；有空格的 `MAP3D_LOAD_AT` 要用 `env "MAP3D_LOAD_AT=…"` 帶，不然 shell 會當成指令）：`MAP3D_LOAD_MAP=hongkong MAP3D_LOAD_BUY=all swift test -c release -Xswiftc -enable-testing --filter Map3DMapLoadReportTests`

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
- **牆鐘很吵**（同一份程式兩次差 10–20 %）：比改前改後要用 `git worktree` 另建一份 `main`（同樣加 `-O`，從頭建約 13 分鐘），
  兩邊交錯跑、每格取中位數；不要邊編譯邊量。
- **逐函式看時間用 callgrind**（雲端有 valgrind，沒有 perf）：直接跑測試的執行檔，等報告印出場景指紋再開始記，只記一兩個區塊：

  ```sh
  R=.build/out/Products/Debug-linux-x86_64/GamePresentationTests-test-runner
  env "MAP3D_LOAD_AT=Mong Kok:22.3193:114.1694" MAP3D_LOAD_MAP=hongkong MAP3D_LOAD_BUY=all \
      stdbuf -oL valgrind --tool=callgrind --instr-atstart=no $R GamePresentationTests.Map3DMapLoadReportTests > run.log 2>&1 &
  until grep -q "one chunk 2 km east:" run.log; do sleep 3; done; callgrind_control -i on
  until grep -q "5 x 5 chunks 3 km east:" run.log; do sleep 5; done; callgrind_control -d; pkill -f valgrind
  callgrind_annotate --inclusive=yes callgrind.out.*.1 | swift-demangle --simplified | head -80
  ```

  一個 5 × 5 區塊在 callgrind 下約 100 s。報告測試自己的 `digest` 也被記進去（約三成），看的時候扣掉。

## 這次量到、還沒動的（評分在私有庫 `docs/priorities/PERF-3D-DRAW.md`）

1. ~~地下車站的整網計算（PERF-3D-UNDERGROUND-MEMO）~~ **做完**（工作串「加快地下車站的 3D 建構」，分支 `claude/project-thread-a8lk3q`，
   決策 876「後來」）：`Map3DSharedBuild.undergroundStations`，鑰匙是路網指紋、隧道裡每座月台、場景原點。福岡一個區塊
   0.33–0.48 → 0.09 s（debug `-O`），福岡與香港 20 個指紋相同。**香港沒有變快**：它的 track cover 步驟本來只有 0.02 s，
   上一輪猜錯了；香港一個區塊的 0.4–0.8 s 在下面第 2 項那些步驟。福岡改後剩下的 0.06–0.10 s 在「the player's track and platforms」
   （`addTrack` 的 `undergroundStations.outside`、`addUndergroundPlatforms`），沒有拆開看，併進第 2 項。台灣全買沒有重量。
2. ~~道路橋與隧道、土地覆蓋與水每個區塊的固定成本（PERF-3D-BLOCK-FIXED）~~ **做了一部分**（工作串「加快香港 3D 區塊的建構」，
   分支 `claude/project-thread-qpmp0i`，決策 876「後來（PERF-3D-BLOCK-FIXED）」）：拆開看不是固定成本，是每個區塊按面積做的
   道路工作（決策 865 的路床與擋牆、決策 391 的橋面、道路與標線）加建物輪廓，最花時間的是它們一再查的表。改成格子鑰匙用快的
   雜湊、地面角點放陣列、高度檔的列與 PMTiles 的目錄記住、沒有橋的格子不複製橋面資料：香港全買 20 個區塊時間加起來
   19.0 → 14.3 s（少 25 %），整個場景少 22–37 %，25 個指紋相同；羅瓦涅米快一倍多、福岡快 20–60 %，15 個指紋也相同。**剩下的**：香港一個 5 × 5 區塊仍是
   路床（`roadBed(of:)` 沿每條路每 2 m 量地面）、擋牆、橋面、道路條帶與標線各一成上下，再來是建物輪廓。要再快得改演算法
   （路床的取樣共用給擋牆與條帶；或只建要留的格子，不建外圍 256 m 的緩衝），會牽動「單獨建的區塊與整個場景相同」，要另外
   設計與證明（評分在私有庫 `docs/priorities/PERF-3D-DRAW.md` 的 PERF-3D-ROAD-BED-SHARE、PERF-3D-APRON）。
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
