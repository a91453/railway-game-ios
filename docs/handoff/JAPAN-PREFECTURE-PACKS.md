# JAPAN-PREFECTURE-PACKS 交接（決策 991）

分支 `claude/project-thread-qth4v9`，PR #2708。這張 PR 做的事寫在 `docs/decisions/991.md`。下面是之後要做的。

## 1. 下一張：開局畫面選福岡、佐賀、熊本

**已做（決策 999，分支 `claude/project-thread-bmca7p`）**：選地點清單裡日本一個開局點一列（「日本：從福岡開始」等），
照 `starts` 自動列，長崎包加開局點就多一列。下面是當時的交接。

作者 11-26：「開圖也能選 熊本開局 福岡開局 佐賀開局等」。

- 資料已經在這張 PR 裡：
  - `pack.json` 的 `starts`，讀成 `MapPack.Layout.starts`，每個有中、英文名與座標。
  - `GameWorld.newOverseasGame(_:start:)` 依編號開局。
  - 測試：`MapGrowthLayoutTests.testANewGameBeginsRoundTheCityPicked`。
- 要做的只有畫面：開新局選日本地圖時，多一排「從哪裡開始」（福岡／佐賀／熊本），把選的編號傳進 `newOverseasGame`。
  - 呼叫點在 `GameLauncher.swift`，搜 `newOverseasGame(`。
  - 只有 `layout.starts.count > 1` 的地圖顯示這排。
- 等 OVERSEAS-BUY-LAND（分支 `claude/project-thread-f5vos0`）合了再做，它也在改開新局與 `GameLauncher`。它會在
  `grown()` 改一行（`grown.mapExpansion == nil && !grown.wholeMapOpen`），和這張 PR 的 `grown()` 可能衝突，
  合併時兩邊都留。
- 這是畫面改動，依 ui-review 要截圖。

## 2. 新機場飛台灣的航線

熊本、佐賀、北九州、天草機場這次沒有列飛台灣的航線，都算在「其他國際線」。要補的話：

- 查民航局《民航統計年報》2025 年表 50-1、50-2（桃園、高雄的國際航點）裡熊本、佐賀、北九州的旅客與架次。
- 台灣端（`taoyuanRoutes`、高雄的 routes）和日本端（三座機場的 routes）一起補，`destinations` 加 `kmj`、`hsg`、`kkj`。
- 台灣存檔的機場航點會跟著變，對照 `AirRoutesTests`。

## 3. 舊存檔看不到西半與北邊

舊局鋪在 `older`（西北角 N 33.72、W 130.29），看不到唐津、佐賀市西半、北九州。要讓舊局也看到，得先讓
GameCore 能把整個世界往東南平移（所有座標加一個位移），規模和風險都大，這次沒做。玩家想要就開新局。

## 4. 重做地圖包

指令照 `tools/fukuoka-map/README.md`：先 `build_fukuoka_ground.py` 的各步，最後 `split_prefectures.py`。

- 拆過以後再跑會停下來，要先重做整張。
- `build_fukuoka_rail.py` 的 `write_manifest` 只依 `SOURCES` 重寫檔案清單，會把九州新幹線那兩個檔的條目弄掉。
  - 拆之前先從 git 把 `pack.json` 拿回來（`git checkout -- RailwayGameApp/Resources/MapPacks/fukuoka/pack.json`）。
  - 再跑 `split_prefectures.py`，它會更新範圍、開局點與 `older`。
