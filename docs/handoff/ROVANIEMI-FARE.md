# ROVANIEMI-FARE（含 ROVANIEMI-PAIR）

## 進度

- 做到哪：併了 main（羅瓦涅米那節改 §29.29）；報告加了反過來的買法（`ROVANIEMI_ONLY`）；release build 好了（Linux 約 38 分），正在量 MUL→KJA 30 天。假說：起站的旅次照吸引力分給到得了的站，再照分鐘衰減，遠的站分走的大多消失（`PassengerDemand.dailyDemandDetails`）。
- 已驗證：無。
- 下一步的第一個指令：`ROVANIEMI_REPORT=30 ROVANIEMI_ONLY="vr:MUL+vr:KJA" swift test -c release --skip-build --filter RovaniemiReportTests`（結果在 scratchpad `rev30.txt`）。

session_01JMHz9bnKhejDxHKpyueHQ3，分支 `claude/rovaniemi-fare`（從 `claude/rovaniemi-open`，含 #2355），決策 828。
