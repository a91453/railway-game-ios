# DEPOT-DAWN-QUEUE（2026-11-18）

- 派工：新專案協調者（DEPOT-DAWN-QUEUE 併 TCL-DAWN，南港島綫尖峰不在範圍）。雲端 Linux，分支 `claude/project-thread-r1u9ok`，決策 841。
- 存檔版本不動（108）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。**GameCore 沒有改**（量測的程式在 `c70b059`，下一個 commit 拿掉）。

## 做了什麼

- 在 `main` `081a701` 量了 29 個世界兩種規則的基準（雜湊在決策 841 末）。
- 加了追蹤（`TRACE_DEPOT`），逐分鐘看清晨每一站的出庫判斷：提前量算得對，是出庫車被前一列出庫車擋住出不去（決策 841 §2）。
- 寫了四種提早出庫的寫法、各量 29 個世界：都沒過門檻（多死結或多漏班），沒有收（決策 841 §3）。
- 留下兩項，評分在 `docs/priorities/DEPOT-DAWN-QUEUE.md`。

## 下一個 session 怎麼接

第一個指令（重現東涌綫潛伏的死結，約 3 分鐘）：

```sh
git checkout c70b059 && swift build -c release -Xswiftc -enable-testing --build-tests
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_ONLY=hk-tcl DAWN_QUEUE=2 DEPOT_RETURN_STUCK_MIN=4 \
  .build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testHongKong
```

- 先修 TCL-DEPOT-CLAIM（第一天 11:21 起，10 號空車 11:11 從香港回小蠔灣，claim 綁住東涌的 4、9 號）。修好後 `DAWN_QUEUE=2` 那一版也許就能收：它在其餘 28 個世界逐字不變，東涌綫 3 → 2 班。
- DEPOT-DAWN-QUEUE 本身要動跟車（`RouteReservation.swift` 的 `isLeading`、`followingAuthority`）。機捷的長庚醫院站要量的是：往體育大學站、台北車站的出庫車先走，往長庚醫院站的跟在後面，是否接得上 05:56–06:07。
- 讀 `.claude/skills/depot-work/SKILL.md` 第 5 節，這次的四種寫法加在表裡了。

## UNVERIFIED

- 第 2 節「為什麼不能跟」是讀程式的推測，沒有在 `isLeading` 裡逐條印出來確認。
- 量測都是 Linux release；擬實規則只量了 `main` 的基準，四種寫法只量了簡化＋管制。
- iOS、實機沒有看（沒有改 App）。
