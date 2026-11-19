# DANHAI-REBUY-PLACE＋DANHAI-OLD-SAVE（綠山線刪掉再買回來跑位、舊存檔先藍海再綠山月台不同高）

派工：協調者，2026-11-18（評分 `docs/priorities/BUG-HUNT-1118.md` 第 4 項 2.45，在私有庫）。session：雲端工作串「修綠山線重買後車站跑位」，分支 `claude/project-thread-fbzqmn`（疊在 #2484、#2477 上）。

決策 493 的「後來」。只改 GamePresentation；GameCore、存檔版本、golden、ReplayFixtures、決策號都不動。

## 做了什麼

- 淡海兩條線一起買、刪綠山線、買回來：每座月台回到第一次買的位置。原因是綠山線被當成「鋪在藍海線旁 30 m」（決策 493），但一起買時藍海線只從濱海沙崙起。`RealBranchLine.isLaidAlong`：另一條線真的鋪在共用那一段才這樣賣。
- 舊存檔先買藍海線、再買綠山線：9 個共用站裡 8 站同高（原本 7 站差 10–17 m）。鋪在旁邊的線找真實高架的範圍加上 30 m 偏移；「跟著已有月台的高度」鋪不上時改成能跟幾站就跟幾站（原本整條放棄）。
- 三條都是所有地圖共用的規則；`SHARED_STATION_REPORT` 的其他地圖逐行不變。
- `RealLineBoughtAgainTests` 的 `elsewhere` 例外拿掉了。

## 還留下什麼

1. **DANHAI-HONGSHULIN-LEVEL**：先藍海線再綠山線時，紅樹林兩條線的月台還差 2.6 m（都在高架，相距 10 m）。綠山線的紅樹林是六股的端點，平段比藍海線的長，坡度到不了。只有決策 862 之前單買藍海線的存檔遇得到。評分在私有庫 `docs/priorities/DANHAI-REBUY-PLACE.md`。
2. 先藍海線再綠山線的收購卡會多鋪兩三次才出報價（「跟著月台」第一次被拒之後再試）；Linux debug 上整個測試 3 → 約 6 秒，沒在裝置量。
3. 已經買成舊鋪法的存檔不會自己改（同 SHARED-LEVEL-REBUILD）。
4. 整張台灣地圖全買之後的刪掉再買仍沒測（同 LIUJIA-REBUY 第 4 項）。

## UNVERIFIED

- 沒在 iPhone、iPad 上看過買回來的綠山線，也沒看過舊存檔補買的樣子。沒有新畫面，不拍截圖。

## 怎麼重跑

```sh
stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.RealLineBoughtAgainTests/testDanhaisLinesAreBoughtAgain"
SHARED_STATION_REPORT=/tmp/shared.txt stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.SharedStationLayoutTests/testReport"
```
