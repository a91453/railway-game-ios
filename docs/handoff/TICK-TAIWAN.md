# TICK-TAIWAN（2026-11-18）

## 進度

- 做到哪：五項改動做完（決策 878「後來」），併了 main（含死結清查 #2485、決策 877），開 PR。
- 已驗證：main `3f207d1` 與 `dbaf899` 上台灣全買簡單、寫實各到 10 時，新舊 build 的 10 個整點雜湊逐一相同，時間少 41–51 %（表在決策 878「後來」）；GameCore 相關測試約 250 個與新測試 `TrafficPairsTests` 過。
- 下一步的第一個指令：見下面「還留下什麼」第 1 項，先 `perf` 取樣再動手。

## 派工

- 協調者派工（作者：「改用opus繼續」），雲端工作串「加快台灣全買的模擬 tick」，分支 `claude/project-thread-cffaib`。接 TICK-REAL（決策 878，`docs/handoff/TICK-REAL.md`）留下的第 7 項。
- 存檔版本、決策號、golden schema：不動（寫成決策 878 的「後來」）。`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 沒動。

## 做了什麼

在 main 的台灣全買簡單晨峰（08:00–08:40）取樣，熱點和香港完全不同：`trafficPlan` 45 %（其中 `planTrafficOvertakes` 30 %）、
找路時的 `sidings(except:)` 24 %（每個月台都從頭找一次車站）。改了五項，都是「同樣的問題給同樣的答案、只是少找幾次」，細節與「為什麼結果一樣」在決策 878 的「後來」：

1. `sidings(except:)`：各站是不是機廠先查一次，不再為每個月台重找車站。
2. `planTrafficOvertakes`：只看共用兩站以上的列車對（`trafficPartners`），共同點用各站的第一個點查表。
3. `preferredTrafficCommon`：每列車的分段與「各段各站第一個點」整份計畫算一次（`TrafficRuns`）。
4. `preferredTrafficSharesCorridor`：每列車兩點間的軌道段在一份計畫裡借用（`TrafficPlan.corridors`）。
5. `planHeadwayOvertakes`：快車沒經過慢車所在站的列車對不問；`trafficOppositeCounts` 在同樣的班次組合下借上一份計畫的（`TrafficParts.opposite`）。

新測試 `TrafficPairsTests`：`trafficPartners` 和暴力比對相同；`preferredTrafficCommon` 和舊的逐點掃描相同。`TrafficPlanKeptTests` 也涵蓋第 5 項的借用（借來的計畫和從頭算的一樣）。

## 怎麼量

照 `docs/handoff/TICK-REAL.md`「怎麼量」。台灣只驗雜湊時用 `SAVED_WORLD_TICKS=600`（到 10 時，含晨峰）。
三個程序同時跑在 4 核機器上會互相拖慢（數字只能看相對）；**一邊建置一邊跑三個量測會讓雲端容器記憶體不夠被重開**，`/tmp` 的存檔與 build 全沒了：量測檔放在家目錄。

## 還留下什麼

改後再取樣（台灣簡單晨峰，第 1–4 項做完時）：`trafficPlan` 31 %、`takingDeparture` 21 %（其中 `reserving` 6.5 %、`opposingParts` 5.6 %、`path` 4.5 %）、
`trackHolders` 18 %（`Train` 逐列相等 5.7 %）、`planTrafficOvertakes` 15 %（`overtakeTrackFree` 10 %、其中 `trafficOppositeCounts` 4.4 %、`trafficAssignedSiding` 1.9 %）、
`extendAuthorities` 12 %、`planHeadwayOvertakes` 9.8 %、`runDepotEntryCandidates` 8.9 %。第 5 項之後沒有再取樣。

1. **計畫一步就重算一次**：`trafficPlan(memo:)` 的鍵含每列車的執行位置與到開時刻，149 列車幾乎每一秒都有一列變，所以每一步都整份重算。要再省得改成「只重算變了的列車與它的對手」，要證明待避推論的順序依賴（`proposals` 依列車對順序、`rebuilt`／`relied`）不變。風險高，要像 `answerAudit` 那樣配稽核（每份增量計畫與從頭算的 `waits` 相等）。
2. **`overtakeTrackFree` 掃全部列車的全部點**：可以用車站索引（`TrafficMeetIndex` 的做法）只看那一站的點，順序照列車、點的順序。
3. **`trafficAssignedSiding` 掃全部列車的全部點**：同上。
4. holders 那一層（`trackHolders`、`extendAuthorities`、`reserving`）是決策 877 剛改過的地方，照 `docs/handoff/TICK-REAL.md` 第二批。

## UNVERIFIED

- 實機的 tick 時間與倍速手感（iPhone／iPad）。
- 台灣全買一整天（只跑到 10 時）；香港、羅瓦涅米沒有重跑（改動是通用的，靠 golden、重播與 CI 的全部分片）。
- Apple 平台編譯與完整測試、整天的時刻表體檢：交 CI。
- 時間是雲端 Linux、三個量測同時跑時量的，只能看相對；雜湊是硬的。
