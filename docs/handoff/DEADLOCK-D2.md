# DEADLOCK-D2（2026-11-17）

- 派工：遊戲規劃（接 `docs/handoff/DEADLOCK-D1.md` 的「還留下什麼」第 1–3 項與「D2 要怎麼接」）。session `session_01JMHz9cHtwbozn4hmcJeXBL`，雲端 Linux，分支 `claude/deadlock-d2`。
- 決策 810（`docs/decisions/810.md`）。存檔版本 107 不動（108 沒有取）；golden schema 77 不動；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 一個值都沒變。
- **這個 session 壓縮兩次，照規定停在這裡。** 派工單三件事只做完一部分，下面寫清楚哪些做了、哪些量過不行、哪些沒做。

## 做了什麼

- **收進來的只有一條規則**（決策 810）：跟車的列車要停的股道被這條線的備用車占著時，還在路上就改去同一站空的股道，不停車（`Deadlock.swift` 的 `berthChange(memo:)` 與新的 `diverted(_:along:left:)`）。
  羅瓦涅米兩條線整天 0 分鐘死結（`main`：KJA 1 分鐘、MUL 3 分鐘），`RovaniemiRailwaysTests` 改成「整天 0 分鐘」。
- **另外三條寫了、量了、沒有收**（決策 810 第 6 節有表）：A1（出發時做決策 740）在機捷舊線一次都沒用到；A2（擬實下出發時做決策 571）讓死結分鐘 42 → 47；C（收班後去另一座機廠）讓簡化規則沒發的班 6 → 17。
  三條的程式在分支的第一個 commit `278c6a8`（帶量測開關 `PROBE_NO_A1/A2/B/C`），第二個 commit 拿掉了。
- **派工單第 1 項（多漏的那一班）查到成因，沒有修好**：見下面第 1 項。
- `DepotReturnReportTests` 的 `DEPOT_RETURN_STUCK_MIN` 多印一段（留在版裡）：每一列卡住的車在等誰、在哪一段、對方是不是備用車、有沒有表列月台、`takingAnyDeparture` 的結果。查短死結的成因用這個。

## 還留下什麼

**先看這個：機捷新線、擬實規則，這個分支比 `main` 多漏一班（1/333 → 2/333，05:56 長庚醫院站往台北車站）。** 派工單的門檻「不可以比 `main` 多漏班」在這一格沒有守住，請規劃決定收不收。
同一格白天的死結 77 → 68 分鐘。沒有查當下缺的是哪一列；成因很可能和下面第 1 項同一類（清晨長庚醫院站第一班靠蘆竹機廠出庫，白天的車位一變就來不及），這是推測。
查法：`--filter DepotReturnReportTests/testTheTaoyuanAirportLine`，`DEPOT_RETURN_WATCH`、`DEPOT_RETURN_WATCH_AT` 看第二天 05:30–06:10 蘆竹機廠附近的列車，和 `main` 比。
（玩家 3、開發 3、美術 1、鐵道迷 2、音樂 1 → 2.25；bug 類。）

分數是五個角度各 1–5、照 `docs/research/NEXT_PRIORITIES_2026-10-12.md` §19 的權重（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。

1. **機捷舊線、簡化規則、管制開：沒發的班還是 6（決策 808 之前是 5）。** 這個分支沒有動到這一格（雜湊與 `main` 相同，`e2fed75ae03f66ee`）。
   - 查到的（逐分鐘比兩邊，已驗證）：05:56 長庚醫院站往台北車站那一班，決策 808 之前是 8 號 05:45 從蘆竹機廠出來接的。
     決策 808 之後，30 號（00:30 起停三重站）與 31 號（00:26 起停機場第一航廈站）收班時蘆竹機廠滿了，整夜停在月台。
     05:40、05:41 蘆竹的頭幾列出庫後有了位置，兩列才進庫（31 號 6.3 公里；30 號從新北產業園區站起 24.2 公里）。30 號的整路預約占著出庫的路，去長庚醫院站的車 06:07 才出來。
   - 試過的修法 C（整條線收班後，等不到位置的車去另一座機廠；`RunDepot.swift` 的 `otherDepotRun` 加 `isAtRest`）：沒發的班 6 → 17，05:56 還是沒發。不要再走這條。
   - 沒試的方向（都是猜測）：(i) 清晨有班要從機廠出來時，出庫排在「多出來的車進庫」前面；(ii) 整夜停在月台的車，清晨直接接離它最近的那一班，不先進庫；(iii) 進庫的路很長（這裡 24 公里）時不要整條訂下來。
   - **09:10 機場第二航廈站那一班沒有查。** 量測的 log 在這個 session 的暫存區，不會留下；要重跑（下面「怎麼重現」）。
   - （玩家 3、開發 3、美術 1、鐵道迷 2、音樂 1 → 2.25；是 bug 類，排在功能前面。）
2. **擬實規則白天的短死結（案例 4）大致沒有變少。** 機捷舊線 42 分鐘、重建線 67（這個分支與 `main` 相同）；新線 77 → 68。
   - 查到的（已驗證，機捷舊線兩天 32 段）：每一段出發的車都**沒有表列月台**（不是決策 740 的形狀，D1 交接第 3 點的猜測在這裡不成立）；
     幾乎都是要出發的班次，下一站（機場第一、第二航廈站）的月台上停著兩趟之間的備用車。17 段是決策 571 等到整分鐘才做，7 段由 `resolveDeadlock` 最後一串解開，1 段是改股道，其餘是擋路的車在同一分鐘內自己被派走。
   - 試過的修法 A2（出發當下就做決策 571）：決策 571 整分才解的 17 → 4，可是死結分鐘 42 → 47、最多同時 3 → 5（傍晚第二航廈站出現五列互等）。不要原樣再走這條。
   - 沒查完的推測：提早逆向進空月台後，車停在另一邊的月台，下一趟出發時和進站的車對頭。下一步應該先看 A2 版第一天 19:34 那五列各自在等誰（`DEPOT_RETURN_STUCK_MIN=1`），再決定是限制 A2 的條件還是換作法（例如讓備用車停在不擋到發的那一股）。
   - 量測的方式本身會把「不到一分鐘、調度第一眼就解開」的等待算成一分鐘（每分鐘 tick 之後、調度之前取樣）。要分辨玩家看得到的與看不到的，報告得多一個「連續兩分鐘以上」的數字。
   - （玩家 3、開發 3、美術 1、鐵道迷 2、音樂 1 → 2.25）
3. **A1（出發時做決策 740）沒有收。** 沒有量到好處、沒有單元測試。要收的話先找一個真的有表列月台、而且表列月台會被備用車占住的世界（機捷舊線沒有），再寫測試；`PlatformListTests.testWithEveryPlatformOfTheListTakenTheTrainWaits` 要照舊通過。
   （玩家 2、開發 2、美術 1、鐵道迷 2、音樂 1 → 1.7）
4. **決策 810 的規則只在「擋路的是備用車」時提早改股道。** 擋路的是剛收班的車時照舊等到走不下去（決策 278）。這是故意的（第 2 項 A2 的教訓），不排。
5. D1 交接第 4、5、6 項（傍晚台北車站六段一分鐘、三列跟車繞一圈、`docs/OVERVIEW.md` §2 的 fixture 數）這次都沒有碰。

## 怎麼重現

- 羅瓦涅米：`swift test --skip-build --filter RovaniemiRailwaysTests`（`main` 的規則下 KJA 有 1 分鐘、MUL 有 3 分鐘死結；這個分支兩個整天測試要求 0 分鐘）。
- 改股道的單元測試：`swift test --skip-build --filter BerthChangeTests`。
- 25 個世界：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_CHECKSUM=1 swift test --skip-build --filter DepotReturnReportTests`（擬實），加 `DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1` 是簡化、管制開。
  只跑一個世界：`--filter DepotReturnReportTests/testTheTaoyuanAirportLineBoughtBefore`（機捷舊線，四核心上單跑約 7 分鐘）。四核心上一組兩種規則約 45 分鐘（三個同時跑）。
- 看卡住的車在等誰：再加 `DEPOT_RETURN_STUCK_MIN=1`。
- 三條沒收的規則：`git checkout 278c6a8` 之後建置，量測時用環境變數 `PROBE_NO_A1=1`、`PROBE_NO_A2=1`、`PROBE_NO_B=1`、`PROBE_NO_C=1` 各自關掉，`PROBE_LOG=1` 印每一次 `resolveDeadlock` 是哪一招解的。
- 注意時鐘：報告裡 `194100` 秒是第二天 05:55（D1 交接寫「05:50 存檔」，其實 05:55 才是那個值）。

## 量到的（debug 建置，Linux，`main` = `fce1797`）

只留決策 810 那一條規則的版本，HEALTH 的世界兩種規則各跑兩天，54 格：

- 51 格雜湊與 `main` 相同（含機捷舊線、重建線兩種規則，新線的簡化加管制開，文湖線，高鐵，台鐵）。簡化加管制開沒發的班每一格都與 `main` 相同。
- `rovaniemi-mul`：死結 3 → 0 分鐘，沒發 0/12、誤點 0 不變，雜湊 `7ffd5a3a06ab2f04` → `4337a5cf314ae995`。`rovaniemi-kja`：死結 1 → 0 分鐘，雜湊相同（`4887eff2193a767b`）。
- **`tymc`（機捷新線）擬實：沒發 1/333 → 2/333**（多了 05:56 長庚醫院站往台北車站），誤點 149/332 → 153/331，死結 77 → 68 分鐘、49 → 44 段，空車 1035 → 908 公里，雜湊 `96b66d4ce9c8e65b` → `225289834efa6054`。

`main` 的基準（之後比對用）：`tymc-old` 擬實 `d864efa0f0cb390a`（1/333、143 誤點、42 分鐘）、簡化管制開 `e2fed75ae03f66ee`（6/333、6 分鐘）；`tymc-rebuilt` 擬實 `40654f29f8efd232`（1/333、67 分鐘）、簡化管制開 `83de63792d7cedeb`（5/333）；`tymc` 簡化管制開 `fb6df02f65d5de53`（4/333）；`wenhu` 擬實 `a024da9f30aad427`（0/532、289 誤點）、簡化管制開 `1bded8352b388d23`（6/532）。

## UNVERIFIED

- 全部在雲端 Linux 的 debug 建置上量與測。iOS 模擬器、實機、Release 建置都沒有跑（規則在 GameCore，沒有動 App）。
- 25 個世界各只跑兩天；更長的局、玩家自己蓋的路線沒有量。
- 第 1 項的三個方向、第 2 項的推測都沒有驗證。
- 作者參考庫這次沒有重新找（決策 810 第 7 節）。
- 完整的測試交給 CI：本機跑了 `swift build --build-tests -Xswiftc -warnings-as-errors` 與 `BerthChangeTests`、`RovaniemiRailwaysTests`、`CounterflowDeadlockTests`、`NightTerminalBerthTests`、`PlatformListTests`、`TerminalPlatformWaitTests`、`GoldenScenarioTests`、`ReplayFixtureTests`、`SavedGameTests`，都通過。
