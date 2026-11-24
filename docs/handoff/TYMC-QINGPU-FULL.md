# TYMC-QINGPU-FULL 交接

## 進度

- 做到哪：做了兩次，都沒有修好，GameCore 沒改。第二次（2026-11-24，決策 966）量到清晨漏班的兩個成因，
  「chain＋edf」兩條規則合起來新線 13 → 4、舊線 4 → 0，但改建後 9 → 11、死結變多，過不了 HEALTH-146 的逐格驗收，沒有收。
- 已驗證（雲端 Linux，debug，`DepotReturnReportTests`，簡＋控）：`main` `d7dcd27` 的基準與
  `docs/research/health-146-2026-11-24/summary.txt` 相同（新線 13/333、舊線 4/333、改建後 9/333）；各版本的數字在決策 966 §3。
- 下一步的第一個指令：`git cherry-pick -n 8cad3bb`（量測開關與追蹤，不可留在 PR 的 head），
  build 後照下面「怎麼量」跑 `TYMC_X=chain,edf` 的改建線，從第二天 07:15 沒發的那班往回看機場段。

## 第二次做了什麼（2026-11-24，決策 966）

派工：協調者 2026-11-24（評分 2.70，HEALTH-146 的簡＋控三格在這張單驗收）。分支 `claude/project-thread-8b6sng`。
決策 966；存檔 113、golden schema 78、fixtures、`CheckupBudgets` 都不動。

### 成因（細節在決策 966 §2）

1. 清晨：前一晚青埔滿、停在環北月台的車 05:28 被送去 22 km 外的蘆竹，整條路訂到 05:42，正好占住蘆竹出口；
   加上出庫照 `line.stops` 近站先走、出庫車不能跟「自己也在跟車」的出庫車，遠站（台北、三重、泰山）的車出不來。
2. 白天：機場第一、第二航廈一帶塞住（第二航廈三股都有車、第一航廈往東月台被往環北的車占著）。
   三個世界白天沒發的班大多在這裡，上一次交接的「15:49 第一航廈那班」是同一件事。

### 量測的開關（commit `8cad3bb`）

- `TYMC_X=chain`：`RouteFollowing.swift` `isLeading`，出庫空車可以跟同一座機廠出來、自己也在跟車的空車（`leadsOutOfDepot`）。
- `TYMC_X=edf`：`RunDepot.swift` `runTrainLeavingDepot`，同一分鐘能走的出庫車裡送截止時間最早的，不是 `line.stops` 排前面的站。
- `TYMC_X=far`、`anylead`：遠站先走的兩種寫法，量過不行，別再試。
- `TYMC_TRACE=<起秒>-<迄秒>`：那段時間每分鐘印每一站出庫的判斷（沒到時間、沒位置、被誰擋、能走、送出）到 stderr。
  「被誰擋」印的是編號最小的那一列，不一定是真正讓 `isLeading` 不成立的那一列，別只看名字下結論。

### 怎麼量（4 核的雲端機器）

```sh
swift build --build-tests            # 改 GameCore 後 2–5 分鐘
R=.build/debug/GamePresentationTests-test-runner   # 要同時跑幾個版本就把 .build/debug 整個複製出來
E="DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_EMPTY_RUNS=1 DEPOT_RETURN_CHECKSUM=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1"
env $E TYMC_X=chain,edf $R GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLine          # 新線 tymc，13–16 分
env $E TYMC_X=chain,edf $R GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLineBoughtBefore   # 舊線 tymc-old，12–13 分
env $E TYMC_X=chain,edf $R GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLineRebuilt       # 改建後 tymc-rebuilt，22–23 分
```

- 只看一段：先用 `DEPOT_RETURN_SAVE=<檔> DEPOT_RETURN_SAVE_AT=<秒>` 存一次（例如第二天 04:00 = 100800），
  之後 `DEPOT_RETURN_FROM=<檔> DEPOT_RETURN_UNTIL=<秒>` 重播，清晨到 08:30 一次 35–70 秒。存檔是某一版規則走出來的世界，換規則後只能比存檔之後的那段。
- 死結裡有誰：`DEPOT_RETURN_STUCK_MIN=<分>`。
- 整天體檢：`TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_RUNS=1 TIMETABLE_CHECKUP_ONLY="tymc:A simple"`，`TimetableCheckupFullTests`。
- 三個世界可以同時跑（各一核）；build log 一行有幾萬字，找錯用 `grep -n "error:" | cut -c1-300`。

### 整天體檢（`tymc:A simple`，第一天）

| | 沒發 | 誤點 | 出庫誤點 | 尖峰間隔 |
| --- | --- | --- | --- | --- |
| `main` `d7dcd27`（與 `CheckupBudgets` 相同） | 13 | 92 | 9 | +31 分（第一航廈 18:22） |
| chain＋edf | 4 | 120 | 10 | +18 分（山鼻 08:14） |

chain＋edf 的體檢是紅的（誤點 120 > 92＋4、出庫誤點 10 > 9）：班都發出去了，但多發的車讓白天更多班晚 5 分以上。
清晨 06:00–07:00 的誤點由 21–27 分降到 5–12 分，多出來的誤點在 07:00 以後。

## 第二次留下的

- **TYMC-QINGPU-FULL 沒修好。** HEALTH-146 的三格仍是 `main` 的數字。重新評分的兩項在 assets-2 `docs/priorities/TYMC-QINGPU-FULL.md`。
- 還沒有人試的方向（都是推測，照我會先做的順序）：
  1. **長的回送空車不要整條路訂下來、也不要整條掛 claim**（簡＋控）。清晨成因 1 與決策 966 §3 的第 2 次死結都是它。
     `ApproachLocking.swift` 的 `homeLimit`、`approachLimit`（決策 849）是「只訂到進站號誌」的先例，現在排除空車（`isDeadheading`）
     與有直達車的線（機捷）；決策 849 的死路表寫了套在中間站會出什麼事，先讀。
     **2026-11-24 試過一次（決策 968），沒有收**：只訂到機廠咽喉前會讓出庫車逆著進庫空車出來，新線整條停擺；接著做看 `TYMC-EMPTY-RUN-LONG-ROUTE.md`。
  2. **機場段白天塞住**：先量備用車為什麼停在第二航廈往西的通過線（決策 954 改過閉塞下的同一件事，簡＋控沒有），
     以及第一航廈往環北的短班折返時占著往東月台多久。這一項不解，任何讓清晨多發車的規則都會讓改建後白天更擠。
  3. 1、2 有一項過了以後，再把 chain＋edf 拿回來量；它本身不是死結的成因（決策 966 §3 的三次死結都不是它起的頭）。
- 每一種都要逐格比三個機捷世界的簡＋控，再量擬實、`tymc:A simple` 整天體檢、板南線、香港四條線與參考戰役。

## 第一次做了什麼（2026-11-21，#2578）

- 派工：協調者 2026-11-21（評分 2.70，assets-2 `docs/priorities/HK-LATE-RUNS.md`）。分支 `claude/project-thread-vmt6de`。決策號、存檔版本、golden schema、fixtures 都不動。

### 沒發的 12 班

5@05:57 泰山、7@05:58 長庚醫院、8@05:59 三重、9@06:00 體育大學、17@06:08 台北車站、40@07:15 台北車站、48@07:33 老街溪、227@15:49 機場第一航廈、270@17:34、276@17:49 機場第一航廈、319@19:30、331@20:00 台北車站。只有前 7 班是清晨；下午與晚上的 5 班是誤點一路傳下來的。

### 原因（量過）

1. **決策 919 換了路以後，晚上的車往青埔跑。** 把 919 關掉（只關指定月台的靠左路）：沒發 4、誤點 103、出庫誤點 8、尖峰 +26。919 選的路（往環北 713…708、往坑口 191–195、往山鼻 546–542、往領航）本身都是跨線較少的合理路，壞的是之後的連鎖。
2. **蘆竹出來的備用車被決策 666 推向青埔。** 蘆竹出庫到機場第二航廈、沒接到班的車，被 `makeWayForDepot`（讓路給進庫的車）推到下一站機場旅館；從那裡最近的機廠變成青埔。決策 556 的救援（`rescue556`，`runTrainEmptyToDepot` 挑第一座有空股的機廠）也從第二航廈送了一列去青埔。傍晚車 4、18、1、12 從蘆竹的車換成青埔的車。
3. **結果：** 21:00 青埔已滿（12 列），整夜蘆竹 16、青埔 12，老街溪 3 列、環北 1 列停在月台。919 關掉時是蘆竹 16、青埔 10，台北車站、第一航廈、第二航廈各停 2 列。清晨台北那一側的班要從蘆竹排隊出庫（決策 841 的 DEPOT-DAWN-QUEUE），趕不上。
4. **15:49 第一航廈那班：** 蘆竹的出庫車（路 …549,765,196…228,744,745,746 進快車月台 746）15:37–15:50 被誤點的直達車 1、9 再被往台北的車 5 擋住，沒出去；919 關掉時 15:43 就出去了。是誤點的連鎖，不是機廠滿。

`TRACE_DEPOT` 一類的記錄在當時的 `probe.diff`（專案共用資料夾的那份已經不在；第二次的追蹤在 commit `8cad3bb`）：出庫每分鐘的判斷（沒到時間、沒位置、被哪一列擋、擋的那列的路）、每小時各站停幾列、進出機廠。

### 試過、別再試（新局 `tymc:A simple`；門檻 12／97+4／10／31）

| 改法 | 新局 沒發／誤點／出庫誤點／尖峰 | 擬實 |
| --- | --- | --- |
| 收班時讓車回「自己出來的那座」機廠（寫在 `runDepotEntry`） | 一次都沒觸發，數字不變 | — |
| 決策 666 讓路時先讓到進庫路上的站（路上沒有站才照舊讓到最近的站） | 13／138／8／+21 | — |
| 只讓到進庫路上的站 | 17／144／15／+75 | — |
| 夜裡（全線兩小時內沒有班）機廠都滿時，停在月台的車空車開到「機廠出庫最遠」的那一端（`runPullOut` 提前量多 10 分以上、那端月台還有空） | 10／112／10／+32：台北那側清晨補回，但白天多出誤點 | 沒量 |
| 同上，只限停在線的兩端的車 | 9／127／10／+31 | 2／15／5／+13（門檻 1／9／4／5） |

協調者轉的前一次（`otherDepotRun` 放開「擋路」條件）也在這表的同一欄：擬實沒發 1→3、新局誤點 97→130。

## 第一次留下的（2026-11-21）

- **TYMC-QINGPU-FULL 沒修好**，評分不變（2.70）。清晨沒發 12 班仍是 main 的數字，`CheckupBudgets` 沒改。
- 還沒有人試的方向（推測）：
  1. 決策 666 讓路的那一步不要讓「剛出庫、沒接到班」的車往離自己機廠更遠的方向讓（讓回機廠，或讓到反方向的站）；上面兩種「讓到進庫路上」不一樣，那是給所有進庫的車。
  2. `runTrainEmptyToDepot`（決策 556 救援）挑機廠時先挑那列車早上出來的機廠，不是第一座有空股的。
  3. 919 只在沒有直達車與普通車混跑的線上用（機捷擬實會少掉 919 量到的 10 班誤點改善，要先量）。
- 每種都要量 `tymc:A simple` 與 `tymc:A realistic`，再量全部世界（`TIMETABLE_CHECKUP=1`）、`hk *`、板南線。

## UNVERIFIED

- 實機（iPhone、iPad）、Xcode、iOS 模擬器都沒有跑（雲端 Linux）。兩次的 PR 都只改文件，不影響遊戲。
- 第二次：擬實、機捷以外的世界、參考戰役、單元測試在 chain＋edf 下都沒有跑。
