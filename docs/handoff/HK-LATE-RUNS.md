# HK-LATE-RUNS 交接

## 做了什麼

- 派工：優先總表 HK-LATE-RUNS（2.60，「先量」），協調者 2026-11-21。分支 `claude/project-thread-h7y70l`，決策 919。存檔版本、golden schema、fixtures 都不動。
- 量到的原因與修法、各世界前後數字：決策 919 §1–§3。
- 修法：往線路指定月台的路也靠左（右）行，靠左的路跨線較少時才換；`GameWorld.crossovers(on:)` 數渡線。測試 `PreferredPlatformKeepLeftTests`。

## 還留下的

1. **TYMC-QINGPU-FULL**（bug，評分見 assets-2 `docs/priorities/HK-LATE-RUNS.md`）：機捷新局（`tymc:A simple`）清晨沒發 4 → 12。前一晚青埔機廠收到 12 列滿了，老街溪的 4 列（車 25、28、7 等）整夜不回機廠（`runDepotEntry` 裡決策 556「續」只讓擋路的車改去另一個機廠），蘆竹那邊清晨排隊出庫。舊版蘆竹 12、青埔 6。
   - 已試、別再試：全線兩小時內沒有班次時，最近的機廠滿了就改去另一個（`otherDepotRun` 放開「擋路」條件）：機捷擬實沒發 1→3、新局誤點 97→130、板南線新局出庫誤點 30→33。
   - 下一步建議：先查為什麼新版晚上進青埔的車變多（哪幾班的指定月台路改了：老街溪→環北那一段從 359,358…354,785,707,706 變成 359,713…706），而不是改收車規則。先讀 `.claude/skills/depot-work/SKILL.md` 與決策 841。
2. **HK-TERMINAL-THROAT**（bug，同一個評分檔）：南港島綫海怡半島只有一條咽喉邊（45 號邊）接三個月台，金鐘也擠，尖峰間隔 +7/+8 分的主因；是鋪線（`real-line-laying` skill）的問題。

## UNVERIFIED

- 實機（iPhone、iPad）沒看過；Xcode、iOS 模擬器、UI 測試沒跑（雲端 Linux）。
- 全日檢查（`TIMETABLE_CHECKUP=1`）在雲端 Linux 跑過，夜間 CI 會再跑一次。
