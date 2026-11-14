# 最重存檔的效能量測與優化（2026-11-14）

作者最重的存檔（`save-2026-11-14 034949`，176 個有旅客的起點站），在作者的 iPhone 17 Pro 上量，再到模擬器和 Mac 上找函式名稱、量改前改後。

## 量法

- 手機：`xcrun xctrace record --template 'Time Profiler' --device <UDID> --all-processes`（用 `--attach <pid>` 在手機和模擬器上都找不到程序）。手機的 trace 沒有 App 的函式名稱（裝了帶 dSYM 的 Release 版也一樣），所以只看每秒、每條執行緒用了多少 CPU。
- 函式名稱：模擬器 Release 版，以及 Mac 上 `swift build -c release -Xswiftc -enable-testing --build-tests` 加一個讀 `HEAVY_SAVE` 的暫時測試（沒進 repo）。
- App 自己的紀錄：`Application Support/Diagnostics/frame-times.json`（每段的畫面時間、CPU/GPU、記憶體、卡頓）。
- 行為不變的檢查：同一個存檔跑 20 個 tick 後把世界存成 JSON，在 `SWIFT_DETERMINISTIC_HASHING=1` 下比 SHA-256，改前改後一樣。沒有這個環境變數時，連同一份程式跑兩次都不一樣（Set／Dictionary 順序）。

## 手機上量到的（main，作者 iPhone 17 Pro）

| 項目 | 數字 |
|---|---|
| 讀檔到能玩 | 約 5 秒：JSON 解碼約 5.2 秒 CPU，接著約 3.7 秒多核心先算旅客路線 |
| 閒置 | 約 30 ms CPU/秒 |
| 2D 快速 | 約 1.2 核；主執行緒約 10%（SwiftUI Canvas 畫圖） |
| 3D 快速 | 約 2–3 核，主執行緒 34%；畫面 CPU 中位數 21.8 ms、p95 33 ms，GPU 7.9 ms；2.65–2.76 GB，3 次記憶體警告；1.7–2.7M 三角形（舊版 130 量的） |
| 離開到主畫面 | 2D 4 秒（JSON 編碼約 1.2 秒 CPU）、3D 3 秒 |
| 回主畫面卡在「儲存中」 | 舊版 130 約 1–2 分鐘：自動存檔本身 3 秒，後面在等 iCloud 同步把每個存檔整份讀兩邊比對 |
| 讀檔後 22 秒單核 | 在 main 上沒重現 |

## 改了的（照作者今晚的順序）

| # | 改什麼 | 改前 → 改後 | PR |
|---|---|---|---|
| 1 | iCloud 同步每輪碰到有存檔排隊就先讓路，下輪再接著做 | 回主畫面要等整輪同步（約 1–2 分鐘）→ 只等自己的存檔（約 3 秒，手機要再確認） | #2195（已合併） |
| 2 | 先算旅客路線分成 4×核心數份，以前每份重建同一張路網圖；改成只建一次共用 | Mac 1.38 秒 → 0.34 秒（每次讀檔、每次需要重算時）；手機 6 核 24 份都在重建 | #2197 |
| 3 | 每台行駛中的車每步都要看「別台車身有沒有在月台軌道上」，以前每台都把車身段算成陣列；改成先用車頭所在軌道與車尾軌道判斷不可能就跳過 | Mac 20 tick 12.0 秒 → 10.1 秒（−16%），結果一樣 | 本 PR |

手機和 Mac 的比例：同一段工作手機大約是 Mac 單核的 1.5–2 倍時間（JSON 解碼：Mac 1.9 秒、手機約 5.2 秒 CPU；路網圖手機核心少，份數 24 對 48）。手機上的實際秒數要再量一次。

## 還沒改、排好的清單（五方評比）

權重：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15。分數 1–5。

| 排名 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
|---|---|---|---|---|---|---|---|
| 1 | 3D 記憶體 2.7 GB、會收到記憶體警告（有被系統砍掉的風險；要用手機量，改到畫面要截圖） | 5 | 3 | 3 | 3 | 1 | 3.30 |
| 2 | 快速模擬剩下的熱點：`freePlatformOnTheWay`／`trainLeavingTowards` 仍是每台車掃全部車（O(車²)），`platformWaits`→`runLeaving` 每次線性找車，大 struct 複製（memmove 約 9%） | 4 | 3 | 1 | 3 | 1 | 2.70 |
| 3 | 3D 畫面 CPU 中位數 21.8 ms（超過 16.7 ms，60 fps 會掉格），主執行緒 34% | 4 | 2 | 3 | 2 | 1 | 2.60 |
| 4 | 離開遊戲時，正在跑的那個 tick 不會停（`stopGameLoop` 不取消進行中的 tick），快速時最多多等一個 tick | 3 | 4 | 1 | 1 | 1 | 2.35 |
| 5 | 存檔 JSON 解碼（手機約 5 秒）與編碼（約 1.2 秒）：換更快的格式或分段 | 4 | 2 | 1 | 1 | 1 | 2.15 |

## 要在手機上確認的

- 回主畫面：剛讀進最重存檔、iCloud 同步正在跑時按回主畫面，「儲存中」應只剩約 3 秒（#2195）。
- 讀檔到能玩的秒數（#2197 讓多核心那段變短）。
- 快速時 CPU 核數（本 PR）。
- 3D 記憶體與警告次數（還沒改）。

## 3D 記憶體（排名第 1）：只起了頭，交給下一串

作者 2026-11-14 定了「一串一件事」，這項改由新串接手。這串做到的：

- 分支 `perf/map3d-memory`（從 main 切，除了這一節沒有改程式）。
- 手機上的數字：最重存檔**在 2D 就用了 1.65–1.69 GB**（`frame-times.json` 的 `memoryPeak`，App 上限 3.3 GB），所以 3D 的 2.65–2.76 GB 裡大約 1 GB 才是 3D 自己的。3D 那組數字是舊版 130 量的；main 版只量了 2D，3D 記憶體沒量。
- 先讀 `MAP3D-CAP.md`（決策 711）：已經有每格三角形預算、軌道抽稀、記憶體警告時卸遠的區塊。它的預算數字（240／160／100 萬、400／700／1,000 MB）沒有在實機上調過，這是最直接的槓桿。
- 跑了 `Map3DFrameLoadReportTests`（`MAP3D_SAVE=<最重存檔> MAP3D_ALL=1`，Mac release），10 分鐘還沒出第一行就停掉了；下一串要嘛只跑一個焦點（不設 `MAP3D_ALL`），要嘛放背景跑久一點。
- 建議的下一步：(1) 用上面的報告看最重存檔每格的緩衝 MB 與三角形，分到 base／city／far／close／props；(2) 另外量 2D 那 1.65 GB 是什麼（世界本身、旅客路線快取、真實地圖資料），因為它跟 3D 疊加；(3) 用手機量 main 版開 3D 的記憶體與警告次數，拿 Debug 版的 `-screenshot-3d-at` 固定地點，改前改後比。
- 最重存檔的備份：`~/RailwayGameDeviceBackups/2026-11-14-before-perf/Saves/save-2026-11-14 034949.json`（作者的 Mac，不在 repo）。量法見本檔「量法」一節。

### MEM3D（2026-11-14 晚，Mac 本機 session，決策 749，分支 `claude/project-thread-r9xb1y`）

- 改了：區塊緩衝上限 `.ample` 1,000 → 600 MB、`.roomy` 700 → 500 MB；火車模型包（約 287 MB）上 GPU 時一個一個放掉 CPU 的頂點，不再兩份並存。原因、數字、沒選的都在[決策 749](../decisions/749.md)。
- **更正上面的 2D 數字**：手機 frame-times.json（main 版，2026-11-14 18:46–18:51）最重那局的 2D 是 **1,087–1,311 MB**，不是 1.65 GB。2D 裡就有模型包 287 MB（讀檔 8 秒後先做好，決策 546）。
- 最大的來源（模擬器 `heap -s`，同一局）：模型包 287 MB、區塊緩衝 360–450 MB（近景）到上限、場景 CPU 網格 276 MB、世界本身（`WorldCoordinate` 80 MB、`LandCell` 67 MB 等）。
- 量法（這次用的）：暫時的 XCUITest 遙控（`ZZRemoteControlTests`，沒進 repo，`launch`／`tapid`／`drag`／`pinch`／`shot`／`dump`），App 用 `-screenshot-3d-view 1500,0,45 -screenshot-3d-at 25.0478,121.5170`（Debug）開在台北車站上空；模擬器上每 5 秒 `footprint -p`，`heap -s`、`vmmap` 看分項。手機上 `xctrace record --template 'Game Memory' --all-processes` 兩次都失敗（Recording failed with errors）。
- 手機備份：`~/RailwayGameDeviceBackups/2026-11-14-before-mem3d/full/`（整個 App 資料容器，288 檔、174 MB，作者的 Mac）。
- 截圖：`/Users/chienlinyeh/Developer/mem3d-shots/`（before／after 的 2d、3d、far）。

VERIFIED／UNVERIFIED：

- VERIFIED（作者的 Mac）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`Map3DModelPackSlimTests`、`Map3DSceneBudgetTests`；app 的 Debug 模擬器建置（`xcodebuild build-for-testing`）；模擬器改前改後量測與截圖（決策 749 第 3 節）。
- **UNVERIFIED：iPhone 實機的 3D 記憶體與警告次數，改前改後都沒量到**（作者那時要用手機，量測停下；手機上留的是 main 的 Debug 版 0.6.0（130），存檔沒動，最重那局在存檔列表的 `save-2026-11-14 111613`）。要量：同一局、台北車站 1,500 m、拉遠等 2 分鐘，讀 frame-times.json 的 `memoryPeak`、`memoryWarnings`。
- UNVERIFIED：`.roomy` 的 500 MB 沒有 6 GB 裝置量過；其餘測試交給 CI。
- 續（決策 749 §8）：拉到最遠外圈缺塊已補，超過上限時改卸畫面外的區塊。
- 手機實機量了一輪（決策 749 末節）：峰值 2,472 → 2,445 MB、警告 0／0，區塊沒碰到上限所以這次的改法沒起作用；改後畫面時間 25 → 33 ms 只量一次、未證實，下一串用固定鏡頭量三次確認。下一步最大兩項：開著 3D 時放掉場景 CPU 網格（約 276 MB）、模型包只上傳這局用得到的車（200 MB 以上）。
