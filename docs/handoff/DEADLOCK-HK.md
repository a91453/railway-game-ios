# DEADLOCK-HK（2026-11-17）

- 派工：遊戲規劃（作者回報：香港地圖 60 倍速，第 1 年 1 月 2 日 02:20 畫面「5 死結」，南港島綫 2、6、10 與東涌綫 2、3、4、9）。session `session_01JMHz9asWDNkcGEygYRFQdt`，雲端 Linux，分支 `claude/deadlock-hk`。
- 決策 816（`docs/decisions/816.md`）。存檔版本 107 不動；golden schema 77 不動。

## 進度（覆寫這三行，不累加）

- 做到哪：修法寫好、建置過了（未 commit）：`RunDepot.swift` 新增 `runTrainToAnotherEnd(in:memo:)`、`endsWithRoom(of:besides:for:)`，`pullOutBerths` 多一個條件；`GameWorld.swift` 的 `resolveDeadlock` 最後接 `runTrainLeavingAFullEnd`。只送去路線的兩個端點（第一版送到中途站青衣，停錯方向的月台，早上反而互等，已改掉）。還沒寫：回歸測試、決策 816、優先清單、PR。`Tests/GamePresentationTests/TmpProbeTests.swift` 是臨時探針，提交前刪。session 壓縮 1 次。
- 已驗證（Linux，main `e85c96b`）：135 與 main 一樣（兩線寫實 00:34 起 5 列、147 分），不是 D1。作者的存檔（私庫 `problem-reports/2026-11-17-deadlock-hk/`，管制開、寫實、閉塞開）在 main 重播 = 同樣 5 列、到 05:55 共 201 分。修好後：兩線新局 147 → 4 分鐘、六線新局 147+ → 4 分鐘（都是一兩分鐘的短等）；作者存檔南港島綫 1 分鐘內解，**東涌綫那一晚仍等到 05:54**（存檔已是 02:33，九龍、奧運的過夜車停在上行正線，東涌到香港的空車路被擋；新局在 00:41 就送走所以沒事）。
- 下一步的第一個指令：看 `scratchpad/hk-all-fix2-4days.log`（六線新局跑到第 4 天 07:00，`grep deadlock`）確認之後幾晚；再寫回歸測試（香港南港島綫寫實規則跑到第 1 天 01:00，`deadlockedTrains()` 不可連續超過幾分鐘）。
