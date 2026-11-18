# TCL-DEPOT-CLAIM（2026-11-18）

- 派工：新專案協調者（決策 841 §6 第 1 項；只修小蠔灣渡線的 claim 死結，不做 DEPOT-DAWN-QUEUE）。雲端 Linux，分支 `claude/project-thread-r8b6db`，決策 850。
- 存檔版本不動（108）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。

## 做了什麼

- GameCore 只改 `Sources/GameCore/Railway/RouteReservation.swift`：`settleClaims` 裡決策 836 那一步，多放開「擋在空車前車出站路上、停在停靠站且到點要開」的車（`isDueToLeave`）。
- 新測試 `EmptyRunClaimDueServiceTests`（小場景，拿掉規則是紅的）；`HongKongDepotTests` 的東涌綫下午那一格改名 `testTheTungChungLineFirstDayHasNoDeadlock`、延長到隔天 00:30。
- 29 個世界（簡化＋管制）在合了 #2440 的 `main` 上量過：香港每晚兩次 5 列死結 → 0、漏班不變；機捷舊線 7 列死結 → 0、沒發 3 → 4；其餘 27 個逐字相同（決策 850 §3）。
- `TimetableCheckupTests.swift`：`hk TCL simple`、`hk AEL+TCL+DRL simple` 誤點 64 → 62、出庫誤點 7 → 6。

## 留下的

- DEPOT-DAWN-QUEUE 照舊（東涌綫 06:17 仍沒發）。決策 841 §3 的 D 可以在這條規則上重量：第一個指令是 `git checkout c70b059` 的 `DAWN_QUEUE=2` 那段搬到現在的 `main`，跑決策 850「重現」的指令加 `DAWN_QUEUE=2`。
- 機捷舊線 09:10、09:53 兩班為什麼沒發，沒有逐分鐘看。

## UNVERIFIED

- 擬實規則沒有重量（閉塞區間不讀 claim）。iOS、實機沒有看（沒有改 App）。
