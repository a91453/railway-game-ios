# FAIR-SINGLE：單線公平輪流（決策 718）

- 派工：作者 2026-11-13，由行車規則比較的 session 派出（作者 Mac 的本機 session）。桌面版規則一項一個 PR 的一項，排在 CLOSE-TRACK（#2123、#2125）、PENDING-CLOSE（#2126）之後；下一項是「道岔轉換動畫」，不在這張單裡。登記在 #2118。
- 分支 `claude/fair-single`，從 `origin/main` `3be350847` 開，**沒有疊在封閉軌道那三個 PR 上**（規則用不到封閉）。決策 718；存檔版本、golden schema 不動；`SaveFixtures/`、`GoldenScenarios/` 沒變；**`ReplayFixtures/long-leg-traffic.json` 檢查碼 2–5 重錄**（單獨一個 commit，理由逐項寫在決策 718 第 7 節；規劃或作者不同意的話 revert 那個 commit 即可，但 `ReplayFixtureTests` 會紅）。
- 來源：作者自己的桌面版鐵路模擬（私人，不在三個 repository 裡），只照規則重寫。對照表在 `docs/decisions/718.md` 第 5 節。

## 做了什麼

行車管制下，停站的班次到點、軌道也讓它走的時候，如果有另一班比它先開始等、要走同一段軌道的反方向、而且擋住那一班的只有正在走的車（或沒有車擋），這一班就讓那一班先走。

- `Sources/GameCore/Railway/FairSingleTrack.swift`：`turnOwed(by:memo:)`、`isOnItsWay(_:memo:)`、公開查詢 `trainGoingFirst(before:)`。
- `RouteReservation.swift`：`reservingDeparture` 包一層（原內容改名 `takingDeparture`）；`awaitedRoute` 讓人的列車回報等的是先走的那一班。
- `GameWorld.swift`：`departService` 的計畫進路與偏好進路補問一次；`secondsUntilARouteFrees` 同步。
- `Deadlock.swift`：`waitingRoute` 只問軌道（不然計畫交會與輪流互相遞迴）。
- `Tests/GameCoreTests/ReferenceFairSingleTrack.swift`（新）、`ReferenceNetworkService.swift`、`ReferenceTrafficControl.swift`、`ReferenceWorld.swift`：測試的參考模型照決策的文字另寫一份規則；`TrafficControlPropertyTests` 逐步對照 GameCore 與它（沒補之前在 seed 0x5EEDA004 case 12 不一致）。
- `Tests/GameCoreTests/ReservationShortcutTests.swift`：語料加上新場景的跟車狀態（replay 在新規則下幾乎沒有跟車了；決策 718 第 7 節）。
- `Sources/GamePresentation/ServiceText.swift`：`routeWaitText` 多一句「讓 ○○ 先走／Letting ○○ go first」。沒有新畫面。
- `Tests/GameCoreTests/FairSingleTrackTests.swift`：測試場景 `SingleTrackFan`（一段單線、兩端各幾股、每股自己一個站）與 7 個測試。

## 還留下什麼

1. 路線派車出庫、從待避處繼續走的列車不參加輪流（決策 718 第 9 節）。
2. 同一秒到點時沒有搬來源的「上次誰贏這次排後面」（要存狀態）；現在永遠編號小的先。
3. 大地圖上的成本沒有量：每次放行多掃一次列車。合併前值得跑一次 tick 成本的報告。
4. 封閉軌道（#2123、#2126）合了之後，補一個「封閉中只剩一股的交會站」的測試。
5. 閉塞區間模式下沒有另外量。

## UNVERIFIED

- 只在作者的 Mac（macOS）跑過建置與相關測試類別（清單在 PR）；Linux 的完整 tier、性質測試的完整輪數、iOS 建置由 CI 驗證。
- 沒有在 App 裡看過那一句新文字。
