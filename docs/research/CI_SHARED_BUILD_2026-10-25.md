# Swift CI：每個分片都自己 build，能不能共用一次（研究，2026-10-25）

決策 411 的研究部分，只寫研究、不實作。session_01Pz4Th4Hr8SAr6iP9gm4sqC（CI 優化）寫，給遊戲規劃決定。要在 `ci.yml` 加 `actions/upload-artifact`、`actions/download-artifact` 或 `actions/cache`，算「新的 action」，要作者同意（CLAUDE.md、派工單）。

## 現況（main 10 個完整 push run，決策 411 列的 run）

- 完整 tier 21 個 job：changes、gate 與 19 個 Swift 分片。每個分片 job 在 `swift:6.4-noble` container 裡各跑一次 `swift build --build-tests -Xswiftc -warnings-as-errors`（`swift-shards.sh build`），再跑自己的測試（`swift test --skip-build`）。
- 190 個分片 job 的 build：中位數 292 s（4.9 分），最短 151 s、最長 338 s。**佔全部 Swift job 時間的 29%**；每輪約 80 分 runner 時間花在 19 次一樣的 build。
- 慢的 runner 上一個分片 job ≈ 測試 11.5 分 ＋ build 5 分 ＋ 開 container、checkout 約 42 s ≈ 17.5 分。17 分的警告線（決策 405）有三分之一的 job 跨過。只重排（決策 411）攤不掉 build 這 5 分。
- 本機（4 核 Linux，Swift 6.4.0）同一個 build 4m52s；`.build` 約 1.2 GB（Swift 6.4 的 swift-build：`out/Products/Debug-linux-x86_64`，`debug` 是它的連結），`tar | gzip -1` 後 358 MB、17 s。

## 做法

### A. 一個 build job，分片下載它的產物（建議）

1. 新 job `swift-build`（`needs: changes`，同一個 container）：build 一次，把 `.build` 打包（`tar` 加 `gzip -1` 或 `zstd`，保留連結），用 `actions/upload-artifact` 上傳，`retention-days: 1`。
2. 每個分片 `needs: [changes, swift-build]`：checkout、`actions/download-artifact`、解開到同一個路徑，直接 `swift-shards.sh run`（裡面本來就是 `swift test list --skip-build` 與 `swift test --skip-build`）。
3. 分片的 container 映像、工作目錄（`/__w/railway-game-ios/railway-game-ios`）都跟 build job 一樣，絕對路徑不變。

估計（要實測）：
- 分片 job：開 container 與 checkout 42 s ＋ 下載、解開 360 MB 約 20–40 s ＋ 測試 11.5 分 ≈ 12.5–13 分（現在 17.5），離 20 分有 7 分。
- 整輪的牆鐘：changes（約 0.5 分）＋ build（5 分）＋ 最長的分片（13 分）≈ 19 分，現在 23.5 分左右（分片本來就各自 build，並行；現在多出的是一次上傳與分片排在 build 之後）。
- runner 時間：少 18 次 build，約省 75 分；多一個 job（22 個），但每個分片 job 短 4–5 分，佔 runner 的時間少。
- 之後可以考慮減回 17 片（job 少一個），或保留現在的片數換餘裕。

風險與要先驗證的：
- **`--skip-build` 在另一台機器上解開的 `.build` 能不能跑**：swift-build 的狀態檔與 `swift test list` 是否只看產物、不重新檢查時間戳。要在一個 PR 上做一次：build job 上傳，兩個分片下載後跑 `swift test list --skip-build` 與一個類別。
- 產物大小：artifact 的儲存配額（public repository 不收儲存費，但有每個 artifact 與總量的上限）；`retention-days: 1` 讓它隔天就刪。
- build 失敗時：分片全部跳過，gate 照 build job 的結果紅（`swift-shards.sh gate` 要讀新 job 的結果；decision 329 的「killed by signal 再 build 一次」移到 build job 裡，照舊）。
- gate 與 `pr_plan` 的部分 tier（`selected-N`）也一樣改成下載。

### B. `actions/cache` 存 `.build`，各分片照舊自己 build（增量）

key 用 `Package.resolved` 與來源檔的雜湊，restore-keys 退到 main 最近的那份；restore 後 `swift build` 只重編改過的模組。

- 好處：分片結構不變，改動小。
- 壞處：幾乎每個 PR 都改 `Sources/GameCore/` 或 `Sources/GamePresentation/`，下游（GamePresentation、兩個測試模組）照樣要重編，估計省不到一半；19 個 job 同時 restore 同一份 1.2 GB 的 cache；repository 的 cache 上限 10 GB，main 與各 PR 的 cache 互相擠掉；debug build 的增量在不同 runner 之間不一定認得時間戳（checkout 的檔案時間是新的），可能整個重編。**不建議**。

### C. 不加 action，只改 build 本身

- `-c release` 加 `-enable-testing` 跑測試：測試本身會快很多，但 `assert` 被拿掉（`precondition` 還在），測的就不是 debug 的語意；build 也會更久。改了「測什麼」，不是 CI 優化該決定的，**不建議**。
- 只 build 該分片需要的測試模組：campaign 分片多半只要 GameCoreTests，但 rest 與一半的分片兩個模組都要，GamePresentation 又依賴 GameCore；省得有限，還要讓 `swift-shards.sh` 知道每片要哪個模組。**不建議**。

## 五方（A 案）

- 玩家：CI 每輪約快 4–5 分，修正和新功能早一點進 TestFlight；main 不會再因為分片逾時變紅。
- 鐵道迷：無。
- 開發：分片離 20 分有 7 分的餘裕，不用每次測試變長就重排；runner 時間每輪省約 75 分，PR 排隊也少。代價是 `ci.yml` 多一個 job、兩個 action（`upload-artifact` 已用在 `ios-build.yml`，`download-artifact` 是新的），gate 的判斷要多讀一個 job。
- 美術：無。
- 音樂：無。

## 下一步

規劃決定要不要做 A；做的話要作者同意加 `actions/download-artifact`（與在 `ci.yml` 用 `upload-artifact`）。實作時先開一個只動 `ci.yml` 的 PR 加 `full-ci` 標籤，量一輪完整 run，再看要不要減片數。

2026-10-25 規劃選了 A，作者授權兩個 action；實作與量到的數字在 `docs/decisions/411.md` 的「續篇：共用 build」。
