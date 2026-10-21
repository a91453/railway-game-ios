# CI 量測（2026-10-21）

> 作者 2026-10-21：「還需要一個session優化ci流程」。遊戲規劃 session_014rYHMtmqA5bEMkBBuKu6PV 派工給 CI 流程優化 session（session_01E8oiGWPQZ2a8wAE8tNvFKk），決策 329。這份是量到的數字；選了什麼、為什麼，寫在 `docs/decisions/329.md`。前一次量測是 `CI_MEASURE_2026-10-16.md`（決策 265）。

## 1. 量了什麼

- **範圍**：GitHub Actions API。
  - `ci.yml`：2026-10-19 00:00Z 到 10-21 23:08Z 跑完的 381 個 run（PR 與 push），2,320 個 Swift 分片 job。
  - `ios-build.yml`：10-20 00:00Z 起跑完的 208 個 run。
  - 合併過的 PR：最後合併的 22 個（#912–#944）。
- **算法**（和 10-16 相同）：
  - job 的時間 = `completed_at − started_at`；
  - 排隊 = `started_at − created_at`；
  - 「到 gate 綠」= gate job 的 `completed_at` − run 的 `created_at`；
  - 「merge main 的 run」= head commit 是把 main 合進分支的 merge commit；它解了哪些衝突，用 `git show --remerge-diff` 看。

## 2. 量到的

### 2.1 Swift CI：沒有在排隊，時間花在最慢的分片

| | run | job 排隊 中位數／p90／最久 | job 執行 中位數／p90／最長 | 到最後一個 Swift job 跑完 中位數／p90 | 到 gate 綠 中位數／p90 |
| --- | ---: | --- | --- | --- | --- |
| PR 完整 tier（17 個分片） | 32 | 0.0／0.1／7.8 分 | 12.9／16.1／19.8 | 17.4／20.5 | 20.5／26.5 |
| PR 部分 tier（多半是 GamePresentation 的 3 個 job） | 179 | 0.0／0.1／2.5 | 14.4／16.4／18.1 | 16.3／18.0 | 20.4／28.0 |
| push 完整 tier | 65 | 0.0／0.1／8.2 | 13.3／15.9／19.9 | 17.0／23.9 | 17.2／24.1 |

- **Linux 不用等 runner**：p90 排隊 0.1 分。10-12 那種 40 個 job 排滿的情形沒有再出現。
- **一個分片 job**：開容器約 0.5 分、checkout 約 0.1 分、建置（`swift build --build-tests`）中位數 2.7 分（p90 3.1）、測試其餘。建置只佔約五分之一。
- **分片已經平均**（完整 tier，每個約 98 次，job 中位數）：最慢 `campaigns-8` 15.9、`rest` 15.8（最長 19.9）、`campaigns-11` 15.5、`campaigns-1` 15.4……最快 `campaigns-13`、`-16` 10.9–11.0。最慢和第二慢只差 0.1 分，再搬 class 省不到 1 分。
- **gate 在 Swift 跑完之後還要等 iOS**：完整 tier 中位數多 1.1 分（p90 7.3），部分 tier 多 4.2 分（p90 12.3）。

### 2.2 iOS App Build（PR）

| | n | 中位數 | p90 | 最久 |
| --- | ---: | ---: | ---: | ---: |
| macOS job 排隊 | 87 | 0.1 分 | 7.2 | 28.9 |
| Xcode build job 執行 | 83 | 19.6 | | 30.2 |
| run 從建立到跑完 | 76 | 21.1 | 29.8 | |

Xcode build job 的步驟（76 次成功，中位數／最長）：UI 測試 8.2／12.6、翻譯匯出 2.9／6.9、建置 2.6／4.5、開機 2.0／9.2、暖機 1.7／4.5。

**所以會改到 App 的 PR（GameCore、GamePresentation、App 都是），gate 綠的時間由 iOS 決定**：Swift 約 17–18 分，iOS 約 21 分，再加上 macOS 排隊。把 Swift 再縮幾分鐘，這些 PR 的 gate 不會更早綠。

### 2.3 最後合併的 22 個 PR

| PR | CI run 數（取消／失敗） | 最後一輪：Swift job 數、到 Swift 跑完、到 gate 綠（分） |
| --- | --- | --- |
| #944 | 1 | 沒有 Swift；gate 25.8（等 iOS） |
| #943 | 1 | 沒有 Swift；1.0 |
| #934 | 5（2／0） | 17、17.8、34.7 |
| #938 | 3（1／0） | 3、18.6、18.8 |
| #935 | 2 | 17、17.9、18.0 |
| #936 | 4（1／1） | 3、17.7、18.4 |
| #940 | 1 | 沒有 Swift；0.8 |
| #937 | 1 | 3、17.9、26.2 |
| #939 | 1 | 17、17.5、24.2 |
| #933 | 1 | 沒有 Swift；0.9 |
| #932 | 4（2／0） | 沒有 Swift；1.4 |
| #930 | 2（1／0） | 3、18.0、23.8 |
| #928 | 2 | 3、17.6、17.7 |
| #931 | 1 | 沒有 Swift；0.9 |
| #926 | 1 | 3、18.0、22.2 |
| #925 | 1 | 3、16.3、45.3 |
| #929 | 1 | 沒有 Swift；0.9 |
| #927 | 1 | 17、19.6、28.4 |
| #923 | 3（2／0） | 3、18.9、49.9 |
| #918 | 4（1／0） | 17、16.8、17.0 |
| #912 | 3（1／1） | 17、20.5、20.6 |
| #924 | 1 | 沒有 Swift；0.9 |

一輪 CI 本身在 17–21 分（等 iOS 時 25–50）。作者看到的「20–40 分」多出來的部分，是**同一個 PR 跑好幾輪**：#934 跑了 5 輪。

### 2.4 重跑：merge main 的 run 佔 Linux 用量的四成

- 10-19 起 255 個 PR run 裡，**49 個（19%）是 merge main 的 run**，其中 18 個是完整 tier。
- 它們用了 **4,867 分鐘** Linux job 時間，佔 PR run 全部 12,262 分鐘的 **40%**。
- 這 49 個 merge commit **全部都解了衝突**：

| 衝突的檔 | merge commit 數 |
| --- | ---: |
| `docs/ARCHITECTURE.md` 或 `docs/OVERVIEW.md` | 41 |
| 只有 `docs/HANDOFF.md` | 7 |
| `project.pbxproj` | 1 |

- **ARCHITECTURE**：每個新決策接在同一個地方（最後一節之後、`## 目前規則摘要` 之前）。10-21 起改成先放「### N. （預約）」，但預約的幾節彼此只隔一行空行，兩個 PR 各填一節，git 還是當成同一處（#934 三次衝突裡兩次就是 324 和 326、327 相鄰）。
- **OVERVIEW**：§2「決策」那一列的號碼範圍（10 次裡每次都不同，例如「1–217、219–307、310、312」）和 §9 索引的最後幾列。§2 那一列 10-21 已改成「見決策索引」，§9 仍要有人補。

### 2.5 被新 push 取消的 PR run

- 10-17 起 326 個 PR run 有 43 個被取消（新的 push 取代舊的，`cancel-in-progress`）。
- 10-19 起有 gate 的 36 個被取消的 run，**33 個的 gate 是紅的（failure）**：`Check the Swift jobs` 看到分片是 cancelled 就判紅。這些紅掉的 commit 已經不是 PR 的 head，不擋合併，但在 Actions 列表與 commit 列表上看起來和測試失敗一樣。

### 2.6 swift-build 本身崩潰

- 2,320 個分片 job 裡，建置步驟因為工具崩潰而紅的只有 1 次：main b28a790 的 push run 39682926653，`campaigns-8`。
  - `swift build` 在 `[Pre-planning 1 / 269]` 之後 19 秒，`DispatchWorker` 執行緒在 libdispatch 的 `_dispatch_event_loop_drain` 存取 0x30 崩潰（`Signal 11`），exit 139，一個檔都還沒編。
  - 同一個 commit 其他 16 個分片都建置成功；之後的 push run 也都綠。
- 其他 6 次建置紅都在 PR，同一輪的每個分片都紅（真的編譯錯誤），exit 1。
- 測試步驟紅的 4 次都是真的測試失敗（`rest` 3 次、`selected-1` 1 次）。

### 2.7 main 的 full lane：從 10-20 14:19 起連續 10 次紅

| run | 啟動 | commit | 建立（UTC） | 紅的 job |
| --- | --- | --- | --- | --- |
| 39438209091 | ios-full-lane | 614375c | 10-20 14:19 | second、lessons、Xcode build |
| 39482364298 | ios-full-lane | e255b0a | 10-20 19:18 | second、lessons |
| 39501622150 | 排程 | e11b17e | 10-20 21:35 | lessons |
| 39526204987 | ios-full-lane | 5040730 | 10-21 01:15 | iPad、Xcode build |
| 39546432319 | ios-full-lane | 01e3c9a | 10-21 04:52 | Xcode build、lessons |
| 39568681667 | ios-full-lane | e7d1e57 | 10-21 08:21 | second |
| 39591723769 | ios-full-lane | 1e23a2c | 10-21 11:24 | second |
| 39620085532 | ios-full-lane | a166cbc | 10-21 14:48 | second |
| 39676381575 | ios-full-lane | 308c019 | 10-21 21:08 | Xcode build、second |
| 39680748935 | 排程 | bc6611d | 10-21 21:40 | second |

- 每次紅的測試不全一樣，有修好的、也有新紅的（HANDOFF §2「main 的 full lane 紅燈」）；從 10-21 08:21 起四次都是第二個 iPhone job（`MapInteractionTests` 的熱度圖列，#944 修）。
- full lane 的結果只在 Actions 頁面上。紅了不會通知任何人，要有人想到去看；HANDOFF §1.3 寫「也盯 main 的 full lane」，但遊戲規劃同時在合併、派工，三次同一行紅了約 12 小時才有人接手。

## 3. 結論

1. **Swift CI 不是等太久的主因。** 排隊是 0；一輪 17–21 分，最慢的分片 job 約 16 分，其中建置 2.7 分。會改到 App 的 PR 由 iOS（約 21 分）決定 gate 何時綠。
2. **主因是重跑**：一個 PR 跑好幾輪，merge main 的 run 佔 PR 的 Linux 用量四成，衝突的八成多在 ARCHITECTURE、OVERVIEW。
3. **full lane 紅了沒人知道**，連續 10 次。
4. **取消的 run 判紅**是外觀問題，不擋合併；**工具崩潰**三天一次。

各項的做法、沒選的方案與五方理由：`docs/decisions/329.md`。
