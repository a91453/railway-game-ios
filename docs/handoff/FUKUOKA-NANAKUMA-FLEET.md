# FUKUOKA-NANAKUMA-FLEET：七隈線車隊與橋本機廠

- 派工：協調者（工作串「補足七隈線車隊並用橋本機廠」），2026-11-20，雲端 thread session，分支 `claude/project-thread-no5552`。
- 決策 897（`docs/decisions/897.md`）。存檔版本、golden schema 不動；GameCore 沒有改。

## 做了

- 七隈線連橋本機廠一起買（接在橋本站線尾，19 股）、23 組車、整天從橋本端排車。整日體檢兩種規則晚點 127／126 → 0，空港線、箱崎線 0；`TimetableCheckupAllBoughtTests.budgets` 福岡兩列調低。
- 排班工具多三個預設關的開關（照遊戲停站算車數、端點恢復時間；線尾機廠用既有的 `DEPOT_ENDS`）。台灣、香港的排班檔重產後位元組相同。
- 測試：`FukuokaRailwaysTests.testTheNanakumaLineIsBoughtWithTheHashimotoDepot`；量測用 `DepotReturnReportTests.testFukuoka`（`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=fukuoka`）、`HashimotoDepotDumpTests`。

## 還留下的

1. **DEPOT-PULLOUT-HOME**（私有庫 `docs/priorities/DEPOT-PULLOUT-HOME.md`）：線中間、離終點不到 1 km 的機廠，出庫空車訂住站前咽喉約 3 分鐘（決策 897 §5）。第一個指令：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=fukuoka DEPOT_RETURN_WATCH=111600-113700 DEPOT_RETURN_WATCH_AT=橋本 swift test --skip-build --filter DepotReturnReportTests/testFukuoka`（要先把 `hashimoto` 換回線中間的那一版才看得到；座標在決策 897 §5 與這張 PR 的歷史）。
2. 機廠不在真實位置（差約 700 m）、22 組沒量、收購價前後沒量、已買的存檔不補：決策 897 §4。
3. UNVERIFIED：沒在手機上看過（七隈線尖峰、橋本機廠在 3D 地圖的樣子）。
