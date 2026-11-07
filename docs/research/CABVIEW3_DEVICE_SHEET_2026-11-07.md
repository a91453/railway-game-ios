# CABVIEW-3 實機量測單（決策 379 續四，2026-11-07）

給作者在 Mac／iPhone 上量，結果回填到決策 379 續四或 HANDOFF §4.54。Linux 的數字只是比例，實機才算數。

## 怎麼開

1. Release 版（TestFlight 或 Xcode 的 Release scheme），iPhone 橫向。
2. 新遊戲 → 買下高雄環狀輕軌 → 跑到第二天 08:00。
3. 速度 10×。

## 要量的

| # | 畫面 | 怎麼量 | 填 |
|---|---|---|---|
| 1 | 2D 地圖，不跟車 | 看遊戲時鐘，用碼錶量真實 60 秒走了幾分鐘遊戲時間；實際 ÷ 設定 ＝（遊戲秒 ÷ 60）÷ 10 | |
| 2 | 3D，跟一台輕軌（車窗或駕駛視角） | 同上 | |
| 3 | 同 2 | 錄 30 秒畫面：被跟的車有沒有「動一下、停一下」 | 有／沒有 |
| 4 | 同 2，Instruments Time Profiler | 一步（5 個 tick）裡最後一個 tick 多久；`TrafficReading` 佔多少 | ms |
| 5 | 機場捷運（另開一局買下），3D 跟普通車經過高架與地下段 | 車和軌道的高度有沒有對不上（車浮起或沉下），尤其高架起降段（P3 c） | 有／沒有，截圖 |
| 6 | 任一線，10× 跟車時按暫停 | 車停在原地，不會先滑一段再停 | 對／不對 |

## Linux 對照（`CabViewTickCostReportTests`，限制在一般手機的 CPU 比例）

| 狀態 | 3D 跟車 10× 實際 ÷ 設定 |
|---|---|
| #1924 前 | 0.10 |
| #1924 後（這個 PR 的基底） | 0.50 |
| 再加 A（交通讀數移出迴圈） | 0.49（不採用） |
| 2D 地圖，不跟車 | 見下 |

重跑：`CABVIEW_REPORT=1 CABVIEW_STEPS=1 CABVIEW_LOOP_SECONDS=40 CABVIEW_CPU=standard swift test --skip-build --filter CabViewTickCostReportTests`，2D 加 `CABVIEW_2D=1`。
