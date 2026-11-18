# DEBUG-138（2026-11-18）

- 派工：新專案協調者（138 發版後例行的除錯）。雲端 Linux，分支 `claude/project-thread-q0rftj`。
- 存檔版本、golden schema、GameCore 不動；沒有新決策（寫成決策 819 的「後來」，預留的 843 釋出）。

## 做了什麼

1. **實機 bug：138 的香港地圖包「使用內建資料」**（作者回報，`differsFromBundled`，手機留著 137 的包）。原因與修法在[決策 819](../decisions/819.md)「後來（DEBUG-138）」：
   - `RailwayGameApp/App/MapPackDownloader.swift`：拿到的包和 App 內建的不同時，`checkForUpdates()` 要新版，下載完再比一次。
   - `.github/workflows/testflight.yml`：地圖包改在 App 之前上傳。
2. 探針（scratchpad，不進 repo）：在 `main` `0067d9f` 的 release 建置（1,857 秒，**0 個警告**）上
   - 香港簡化規則買南港島綫＋東涌綫跑 26 小時，刪線（賣車）、重買、各再跑 6 小時，每 30 分存讀一次：死結 0 分鐘、存讀 0 個問題。
   - 羅瓦涅米（決策 828 國家軌道）兩條線各自買、跑 18 小時、刪線（賣車，留下 1 段 LeftTrack）、重買（照樣是國家軌道，只付車站與車：凱米耶爾維線 NT$ 1,710,000、穆羅拉線 NT$ 2,280,000）、再跑 30 小時，每 10–15 分存讀一次：死結 0 分鐘、存讀 0 個問題。
   - 看了 137→138 動到 GameCore 的程式（決策 828 的遠距需求與國家軌道、決策 836）：只找到一個理論上的上限（下面評分檔），實際的值碰不到，不改。

## 還留下什麼

- 評分在 `docs/priorities/DEBUG-138.md`（一項，1.25，不急）。

- 實機驗收：下一版裝好、開 App 等一下，設定 →「地圖」→「香港地圖」應是「已下載」。還是「使用內建資料」就按「回報問題」，看「地圖包：」那一行與 Console 的 `differs from the app's; updating:`。
- 決策 776 第三段（香港移出 App）照舊等實機「已下載」。

## UNVERIFIED

- `MapPackDownloader` 的 iOS 編譯（PR 的 `ios-build.yml`）。
- 實機下載新版（下一版 TestFlight）。
- `testflight.yml` 的新順序（下一次發版）。
