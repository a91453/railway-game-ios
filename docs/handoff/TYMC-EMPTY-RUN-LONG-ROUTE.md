# TYMC-EMPTY-RUN-LONG-ROUTE 交接

## 進度

- 做到哪：做了一次，沒有修好，GameCore 沒改（2026-11-24，決策 968）。試了「回送空車只訂到機廠咽喉前」兩種寫法（dl、dl＋dlfree），
  三個機捷世界簡＋控都量了：兩種各有一個世界整條停擺，過不了 HEALTH-146 的逐格驗收，沒有收。這一串壓縮兩次，照規則停。
- 已驗證（雲端 Linux，debug，`DepotReturnReportTests`，簡＋控）：`main` `ff28f94` 的三格與
  `docs/research/health-146-2026-11-24/summary.txt` 一字不差（新線 13/333、舊線 4/333、改建後 9/333）；兩種寫法的六格在下面的表與決策 968 §3；
  小場景 `DepotSignalTests` 五個測試在 `TYMC_X=dl` 下都過。
- 下一步的第一個指令：`git cherry-pick -n 82048ef`（試驗的程式與量測開關，不可留在 PR 的 head），build 後跑下面
  「兩次停擺的重現」的第一條，從新線第一天 09:14 青埔機廠口列車 12 與列車 28 對向互等往回看，補上對向的鎖再量 dl。

## 做了什麼（2026-11-24，決策 968）

派工：協調者 2026-11-24（評分 2.70，決策 966 拆出來的第 1 項）。分支 `claude/project-thread-wd2r2c`。
決策 968；存檔版本（112）、golden schema（77）、fixtures、`CheckupBudgets` 都不動。

### 試的規則（commit `82048ef`，開關都是環境變數）

- `TYMC_X=dl`：行車管制開、沒有閉塞區間時，有班表的線上終點是機廠的回送空車，訂位與 claim 只到機廠咽喉前
  （路上最後一個非機廠月台之後的第一個道岔或交叉），進到 1 km 內才訂進去。路不空也照用（跟車也只拿到界線）。
  程式：`ApproachLocking.swift` 的 `depotLimit`、`approachLimit` 兩處、`holdsToItsApproach`；`RouteNeeds.swift` `reserving` 裡多一段。
- `TYMC_X=dl,dlfree`：同上，但照決策 849，整條路空著才只訂到界線；路不空時和 `main` 一樣跟車、整條掛 claim。
- `TYMC_DL=<單位>`：不找月台，改用離終點固定距離的窗（`140800` = 2.2 km 時兩座機廠都落在自己的出入庫道岔）。沒有跑完整的世界。
- `TYMC_DR=<單位>`：改「近了」的距離（預設 64000 = 1 km）。沒有跑。
- `TYMC_X=dump`：每一對起訖印一次路上的月台、道岔與算出來的界線（決策 968 §2 的表就是它印的）。
- `Tests/GameCoreTests/DepotSignalTests.swift`：小場景五個測試，**要 `TYMC_X=dl` 才會過**；規則要收時把開關拿掉、測試留著。
- 連同 `8cad3bb` 的開關（`TYMC_X=chain,edf,far,anylead`、`TYMC_TRACE`），說明在 `TYMC-QINGPU-FULL.md`。

### 量到的（簡＋控；每一格漏的班在決策 968 §3）

| 寫法 | 新線 | 舊線 | 改建後 |
| --- | --- | --- | --- |
| 基準 | 13，死結 4 次 | 4，死結 2 分 | 9，死結 1 分 |
| dl | **第一天 09:14 起死結不解**，14:55 全線 28 列都停 | 1，但第一天傍晚死結合計 25 分（3–7 列） | 7，死結第二天 18:36（10 列，4 分）、18:51 |
| dl＋dlfree | **6，兩天都沒有死結** | **第二天 00:43 起死結不解**，08:11 22 列 | 14，死結第一天 18:37（2 分）、18:56 |

### 兩次停擺的重現

```sh
git cherry-pick -n 82048ef
swift build --build-tests            # 改 GameCore 後 2–5 分鐘
R=.build/debug/GamePresentationTests-test-runner   # 要同時跑幾個版本就把 runner 與 GamePresentationTests.so 複製出來
E="DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_EMPTY_RUNS=1 DEPOT_RETURN_CHECKSUM=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1"
# dl，新線第一天 09:14（三分鐘）
env $E TYMC_X=dl DEPOT_RETURN_UNTIL=33600 DEPOT_RETURN_STUCK_MIN=2 $R GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLine
# dl＋dlfree，舊線第二天 00:43（九分鐘）
env $E TYMC_X=dl,dlfree DEPOT_RETURN_UNTIL=175500 DEPOT_RETURN_STUCK_MIN=3 DEPOT_RETURN_STUCK_ALL=1 $R GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLineBoughtBefore
```

- **dl，新線 09:14**：列車 12（09:08 老街溪回送青埔，跟在桃園體育園區月台的列車 3 後面，人在 edge 617）與
  列車 28（09:11 青埔出庫往環北，跟環北月台的列車 7，人在出入庫線 edge 773，路是 772、582、583、584 … 592）在同一股上對向。
  清晨的出庫車走的是 582 → 703 → 264（另一股）。推測：`main` 上進庫空車的 claim 蓋住出入庫線，兼做擋對向出庫的鎖。
- **dl＋dlfree，舊線 00:43**：三列回蘆竹的空車繞成一圈。列車 19（第一航廈來，edge 499）等列車 18，列車 22（三重來，edge 172）等列車 19，
  列車 18（台北來，跟在 22 後面，edge 167）等列車 22。推測：跟車的列車 18 的 claim 越過前面兩列的界線先占了機廠口。
  dl（跟車也只到界線）在舊線第二天沒有死結。

整個世界的三格照 `TYMC-QINGPU-FULL.md` 的「怎麼量」（每格 14–28 分，4 核可以同時跑 4 個）；`DEPOT_RETURN_UNTIL` 不必配 `DEPOT_RETURN_FROM`。
這一次的 log 在專案共用資料夾 `/mnt/project-files/tymc-empty-run/out/`（`base`、`dl`、`dlfree`、`dlstuck`、`dlfreestuck`、`dump`）。

## 留下的

- **TYMC-EMPTY-RUN-LONG-ROUTE 沒修好。** HEALTH-146 的三格仍是 `main` 的數字。評分不變（2.70），狀態在 assets-2 `docs/priorities/TYMC-QINGPU-FULL.md`。
- 還沒有人做的（都是推測，照我會先做的順序）：
  1. **dl 加上對向的鎖。** 兩次停擺合起來看，dl 少的只有這一道；dl＋dlfree 的毛病（跟車的 claim 越過界線）dl 沒有。
     先查決策 968 §3 沒查的兩件事：列車 12 到界線為止的 claim 為什麼沒擋住列車 28 逆著走的路（決策 836、850 的放開？
     還是列車 28 只拿到 claim 前的那一段就出發？）；列車 28 為什麼選 583 那一股。用上面的重現加 `TYMC_TRACE=32400-33600`
     （09:00–09:20 出庫每分鐘的判斷）。鎖的兩種寫法：出庫車的路逆著一列進庫空車還沒走完的路時不准出發；
     或進庫空車的 claim 對逆向的車仍然算到終點。補了以後先看新線第一天 09:00–10:00，再量三格。
  2. 舊線、改建後 dl 多出來的死結沒看成因：帶 `DEPOT_RETURN_STUCK_MIN=4 DEPOT_RETURN_STUCK_ALL=1` 重跑
     （舊線第一天 18:41 台北、三重一帶；改建後第二天 18:36 山鼻到機場段）。機場段的那幾次可能是 TYMC-AIRPORT-JAM 的同一件事
     （dl＋dlfree 舊線第一天 16:37 那一次就是第一、第二航廈的載客車互等）。
  3. 如果走 dl＋dlfree：跟車的 claim 不要越過前車的界線（或跟在一列停在界線前的空車後面時，自己也只 claim 到界線）。
     新線這一格（13 → 6、死結 0）是目前最好的數字，但改建後 9 → 14 還沒看為什麼。
  4. 界線放在哪的兩個變化（`TYMC_DL`、`TYMC_DR`）與「從長庚醫院回蘆竹等於停在山鼻出站道岔前」好不好，等 1 有結果再量。
- 這張單不管的：出庫的長路（蘆竹出庫到台北 32 km 也是整條訂）是 TYMC-DAWN-CHAIN；機場段白天塞住是 TYMC-AIRPORT-JAM。
- 過了三格以後還要量：擬實（規則只在沒有閉塞時作用，照程式不變，沒跑過）、有回送進庫的其他世界
  （香港東涌綫、安坑、淡海、高鐵、高雄輕軌、三鶯、台鐵、文湖、福岡）、`tymc:A simple` 整天體檢（基準 沒發 13／誤點 92／出庫誤點 9／尖峰 +31）、
  管制關掉的格子、參考戰役、`HomeSignalTests`、`ApproachLockingTests` 與機廠的單元測試。

## UNVERIFIED

- 實機（iPhone、iPad）、Xcode、iOS 模擬器都沒有跑（雲端 Linux）。PR 只改文件，不影響遊戲。
- dl、dl＋dlfree 在機捷以外的世界、擬實、整天體檢、參考戰役、`DepotSignalTests` 以外的單元測試都沒有跑。
- 兩次停擺的成因（「`main` 上進庫空車的 claim 兼做對向的鎖」「跟車的 claim 越過界線」）是從印出來的誰等誰推的，沒有改程式驗過。
