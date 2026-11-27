# BIG-MAP-SLOW（2026-11-27）

## 進度

- 做到哪：玩家回報的「屏東到台南就變慢、60 倍以下跑不滿、點擊延遲」量完，**根因在模擬（GameCore）的 tick，不在 2D 地圖**；程式沒改，只留量測工具與這份交接。當機沒有紀錄，根因不明。
- 已驗證（雲端 Linux 4 核、Swift 6.4、`-c release`）：下面兩張表的數字，`SouthernMapCostReportTests` 兩個測試都跑過。
- 下一步的第一個指令：TICK-HOLDERS-BY-CLAIM 已做（決策 1036，`docs/handoff/TICK-HOLDERS-BY-CLAIM.md`）；照那份交接「還留下什麼」接著做，最慢的是台灣全買・寫實的發車問路。

## 派工

- 規劃 4 工作串「修當機與大地圖卡頓」，分支 `claude/project-thread-jdmc7a`。存檔版本、決策編號、golden schema 都不動。
- 玩家回報（TestFlight 0.6.0 (152)，iPhone 17，三位玩家）：(1) 今天當機；(2) 地圖從屏東到台南就跑很慢；(3-2) 2D 地圖大的時候 60 倍以下也跑不滿、點擊延遲、畫面卡頓。(3-1)「停靠站多不顯示路線、列車不去新加的站」在另一串。

## 當機

- Xcode Organizer 的 Crashes 沒有 152 的紀錄（作者找過），TestFlight 回饋只有一份 145 的截圖回報（編排的 bug，146 已修）。沒有「回報問題」的內容。
- 沒有紀錄就不猜修法。下次請玩家當機重開後一分鐘內按「回報問題」（MetricKit 的當機與卡住診斷會跟著送出，決策 418），或作者從 Organizer 等 152 的紀錄進來（通常晚一兩天）。

## 量到的

### 2D 地圖不是瓶頸

`SOUTH_BOUGHT_REPORT=480`：全台地圖（簡單規則），買沙崙線與高雄捷運紅線（42 站、23 列車、483 段軌道），玩到 08:00，60 倍：

| 項目 | ms |
| --- | --: |
| 一個 tick 在背景算（300 個的平均／p90／最長） | 5.0 ／ 6.8 ／ 11.8 |
| 一個 tick 放回主執行緒（平均／p90／最長） | 0.23 ／ 0.27 ／ 2.1 |
| GameCore tick（60 倍，6 遊戲秒） | 3.3 |
| TrafficReading | 2.0 |
| `LineMap(world:)`（只在路網或路線變了時、在背景算） | 88 |
| `session.buyableRealLines` | 1.3 |

畫布每秒重畫：軌道與路線 0 次、行車控制與車站 10 次（每 tick 都變，本來就是）、列車 10 次、等車人數 3 次。主執行緒每 tick 的工作是 0.2 ms 級，10 tick/秒只占 2–3 ms。

自建屏東—台南（`SOUTH_MAP_REPORT=2`，21 站一條線加紅線、2 列車、318,939 格土地）：每 tick 都在 1 ms 以下，沒重現。

### 慢的是模擬，隨列車數超線性變重

60 倍是每真實秒算 1 遊戲分鐘（10 tick × 6 秒）；一遊戲分鐘超過 1 秒就跑不滿（遊戲照設計改成慢下來，不堆 tick，`startGameLoop`）。TICK-ROUTING（2026-11-25，私有庫 `docs/priorities/TICK-ROUTING.md`）量的一遊戲分鐘：

| 世界 | 列車 | 平均 | 最忙一小時 |
| --- | --: | --: | --: |
| 這裡的南部（上表） | 23 | 約 33 ms | — |
| 香港全買 | 36 | 167 ms | 411 ms |
| 台灣全買 | 150 | 739 ms | 2,188 ms |

所以玩家的路網只要到幾十到上百列車，尖峰時一遊戲分鐘就要超過一秒：60 倍跑不滿。背景算 tick 時 CPU 滿載、手機發熱降頻，主執行緒的手勢與畫面也跟著慢，就是「點擊延遲、卡頓」。之後 TICK-HELD-ASK-ONCE（決策 980，#2691、#2741）已合，被擋的車重問少了；剩下最大的一塊是「誰占哪段」整張重建（`trackHolders`，香港 35 %、台灣 24 %），列車只要位置動了就算「變了」，超過四分之一列車在動就整張重建（`RouteNeeds.swift` `trackHolders(memo:)` 的 `limit`）。

## 還留下什麼

1. **TICK-HOLDERS-BY-CLAIM**（TICK-ROUTING 第 3 列，2.40）：玩家這次的回報就是它的「玩家」分數的實例，建議另開一串做（動 GameCore 全 tier，風險中高：這張表是防撞車的根本）。驗法照 `docs/handoff/TICK-REAL.md`：六個全買世界整點雜湊逐位元相同、`SAVED_WORLD_AUDIT=1` 稽核。注意：列車車身佔的 `TrackSpan` 是路網切好的格子，走過一格就換，所以只比「訂的路與放掉的軌道」不夠，車身也要比；省的是「車身與訂的路都沒變的車」（停站、在同一格裡走）不再拿掉重放、claims 不再重排。
2. 接著同表的 TICK-TRAIN-INDEX（小、風險低）、TICK-PLAN-KEEP、TICK-FREES-FROM-HOLDERS。
3. 這次的量測工具：`Tests/GamePresentationTests/SouthernMapCostReportTests.swift`（不設環境變數就跳過）。
   ```sh
   SOUTH_MAP_REPORT=2 swift test -c release -Xswiftc -enable-testing --skip-build --filter SouthernMapCostReportTests/testWhatASouthernMapCosts
   SOUTH_BOUGHT_REPORT=480 swift test -c release -Xswiftc -enable-testing --skip-build --filter SouthernMapCostReportTests/testWhatTheSouthsRealLinesCost
   ```
   `SOUTH_BUY` 改要買的線、`SOUTH_RULES=realistic` 換寫實規則（全台簡單規則沒有縱貫線可買）、`SOUTH_MAP_SAVE=<path>` 存下世界。release 第一次編要 30 多分鐘。
4. 當機：等紀錄（上面）。

## UNVERIFIED

- 實機（iPhone 17）的 tick 時間、發熱降頻與手勢延遲；玩家實際的列車數。
- 這個測試檔在 `-warnings-as-errors` 下的編譯：交 CI。
