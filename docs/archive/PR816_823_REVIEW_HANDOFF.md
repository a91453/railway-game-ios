# 交接：PR #816、#822、#823 的獨立審查

Session：Codex，作者直接交辦，2026-10-19。審查基準 `main` **3670ffc442a774975e047375bf2a8dc382e2d231**（#825 的合併）。分支 `codex/pr816-823-independent-review`。格式沿用 [上一輪交接](PR755_784_REVIEW_HANDOFF.md)，這次只交報告，修正交原作者。

- 存檔版本：不動；決策編號：不動；golden schema：不動。
- GameCore、ARCHITECTURE、GoldenScenarios、SaveFixtures、ReplayFixtures、workflow 都沒有修改。失敗探針只貼在本文，沒有加入測試 target。
- 已讀三個 PR 的說明、合併 diff、ARCHITECTURE 決策 283／287／288，並追讀行程紀錄、準點率與存檔驗證的呼叫端。#231 登記見 [6266956015](https://github.com/a91453/railway-game-ios/issues/231#issuecomment-6266956015)。
- 以下 **VERIFIED** 都是在 Linux／Debian 13、官方 Swift **6.4.0**（`/opt/swift`）實跑；不代表 iOS 或實機結果。

## 一、範圍與合併狀態

| PR | 決策／主要檔案 | 已合併 commit |
| --- | --- | --- |
| [#816](https://github.com/a91453/railway-game-ios/pull/816) | 283，`RunSpacing.swift`、`GameWorld.swift` 的 service phase | `3dd749c5778f74aff2d2d1985e51666ebdc3df5c` |
| [#822](https://github.com/a91453/railway-game-ios/pull/822) | 287，`BlockSections.swift` 的 `isClear` | `fa2e3ffd0fb84b01add3f6d6c48d2fdd950de861` |
| [#823](https://github.com/a91453/railway-game-ios/pull/823) | 288，`Deadlock.swift` 的 `shortTurn` | `2989b1c8c32831049d64708f22282b89d5e33f3d` |

上述三個 Railway 檔案在 #823 到本次基準之間沒有再變。報告沒有把高鐵整天量測、已知左營夜間出庫死結或 UI 卡片工作重新算成新發現。

## 二、發現總表

| 編號 | 發現 | 嚴重度 | 歸屬與狀態 |
| --- | --- | --- | --- |
| R1 | 折返移動時刻表後，`TrainTrip` 還用舊表；同一趟的 `isLate` 與 `lateTrips` 相反 | P2 | **#823 新增的不一致**；交原作者修 |
| R2 | 折返後第 1–7 秒的存檔不能讀回 | P1 | 提早折返整合的原有缺口；#823 的逐分鐘測試漏掉；交 GameCore 作者 |
| R3 | 分界只檢查車頭，240 m 車身後段仍妨礙岔線 | P2 | **#822 未涵蓋的原有缺口**，不是 #822 新造成；交原作者評估整列車的契約 |
| R4 | `WorldInvariants.violations` 遇到合法的 v28 自動結構直接 trap | P2（測試工具） | 原有參照模型限制；無法宣稱全部 67 份 invariant 都是空陣列 |

P1：可能讓正常遊戲寫出的存檔無法再載入。P2：可重現的紀錄、容量或驗證缺口。**未修任何一項。** 第四節另外列四種開關的行為差異，不冒稱都是這三個 PR 的回歸。

### 三個 PR 之前的對照（VERIFIED）

另外在 detached worktree 的 **b050a538e3d9980c5f7777d968c61e912d52545f**（#816 的 base，三個 PR 都還沒進去）以相同 Swift 6.4 建置及探針實跑，沒有回改本次分支的 GameCore：

| 反例 | 舊版結果 | 本次基準結果 | 歸因 |
| --- | --- | --- | --- |
| R1 | 不提前時刻；實際到站 886、原表 519，trip delay 367、isLate true、lateTrips 1，兩者一致 | trip isLate false、lateTrips 1 | 新的表定時刻未同步到 trip |
| R2 | 241 秒存檔同樣被拒絕 | 241／247 秒被拒絕；248 秒成功 | 原有折返開門狀態的缺口 |
| R3 | 邊界仍為 22,400，仍有 6 筆岔線妨礙 | 相同 | 新檢查沒有補到車尾 |
| R4 | 同一份 v28 在 ReferenceVertical trap | 相同 | 原有測試工具限制 |

舊版 R1 探針的「時刻應已提前」前置斷言會失敗，這是預期的版本差異；不能說整個舊版測試通過。真正用來歸因的是表定到站與準點判斷的一致性。

## 三、每項的重現、預期、實際與建議

### R1：折返後的行程紀錄與準點率使用不同的表

**位置**：`Deadlock.swift:500`–`513` 改這台車的時刻；`TrainTrips.swift:230` 建立行程時複製 `scheduledArrival`，之後沒有隨折返更新；`GameWorld.swift` 的 `recordArrivals` 則用修改後的 timetable 計 `countLineTrip`。

**重現**：附錄 `testShortTurnAfterSaveAndLateTrips`。用既有 `SharedSingleTrackTests.world()` 的 C—A—B 小世界：A—B 接駁車與 C—A—B 的直通車；開 management、line accounts、realistic operation。直通車在 A 提早折返後存讀檔；暫把該車 movement rate 設為 0，等過新表定到站時間 300 秒再恢復。這是合法的延誤指令，沒有改私有狀態或 fixture。

**預期**：依決策 288 的新表計準點率，行程紀錄與路線統計也應使用同一個有效表。已完成行程的 `TrainTrip.isLate` 應與它對 `lateTrips` 的貢獻一致。

**實際（VERIFIED）**：

| 項目 | 秒數／結果 |
| --- | --- |
| 原表終點到站 | 519 |
| 折返時刻／原表回到 A | 240／412 |
| 跳過 B 的到站／發車 | 240／240 |
| 修改後終點到站 | 347（提前 172 秒） |
| 實際到站 | 706 |
| `TrainTrip.scheduledArrival`／`delay`／`isLate` | 519／187／false |
| 對修改後時刻的延誤／路線 tally | 359 秒／`trips = 1, lateTrips = 1` |

本例的 **`lateTrips = 1` 符合決策 288**；錯的是行程紀錄仍說準點，不能反過來把 tally 改成 0 來通過。存讀檔後仍重現；`WorldInvariants.violations` 也抓不到這個語意不一致。

**嚴重度**：P2，玩家查同一趟會看到相反的準點判斷。

**建議修法**：原作者在折返整合處同步更新正在執行的 trip 的有效表定到站時間，或明確分開原始／有效計畫並統一準點判斷的來源；保留實際停靠、票收與上車人數。加一個跨過 5 分鐘門檻的測試，不能只測正常返回時兩邊剛好都準點。若需改存檔或決策，由作者處理。

### R2：折返剛發生的存檔不能讀回

**位置**：`GameWorld.swift` 的 `resolveDeadlock` 在折返當下填 `exchangeEnd`；同檔 `:5020` 的存檔驗證要求有 exchangeEnd 時已過開門時間。

**重現**：附錄 `testSaveOneSecondAfterShortTurn`。同一個 C—A—B 小世界，`.x10` 一 tick 一秒；掃到直通車變成 `.waitingAtStop(3)` 即存讀檔。

**預期**：正常 `advance` 產生的每個可觀察世界都能做 SavedGame round trip；不應依存檔碰巧發生在整分鐘或開門後才成功。

**實際（VERIFIED）**：世界在 **241 秒**，`arrival = 240`、`departure = 240`、`exchangeEnd = 248`。`JSONEncoder` 成功，`JSONDecoder` 拒絕：

```text
Train 2's service times are after the clock.
```

`WorldInvariants.roundTripProblem` 也回報相同錯誤。原因是折返已填 exchangeEnd，但 `arrival + doorOpening = 248 > 241`。同一個探針在第 **7 秒（247）**仍失敗，第 **8 秒（248）**成功。這與時刻表是否提前是兩件事。

**嚴重度**：P1，正常遊戲存檔在這個短時間窗可能無法載入；沒有宣稱既有 fixture 損壞或 App 自動存檔恰好踩到它。

**建議修法**：折返沿用正常到站的開門／交換狀態機，等到開門完成再填開始交換的狀態；若刻意要預排交換，需由作者明確定義並對齊序列化驗證。不要直接刪掉所有時間驗證。加入折返後第 1、7、8 秒 round trip，以及讀回續跑等價測試。

### R3：車頭清空的閉塞分界，不代表整列清空

**位置**：`BlockSections.swift:94` 的 `isClear` 只找碰到 chainage 那一點的 span，不檢查停止姿態的車尾。

**重現**：附錄 `testBlockHeadClearButTailFouls`。1.5 km 的 e1 到 J；J 往東 100 m 的 e2 到 B，再接 e3；e4 從 J 分岔 100 m、向旁偏 6.25 m。16 節標準車，頭尾距離 240 m，從 e1 的 80,000 單位處往東。對授權 envelope 問 `blockBoundary(atOrBefore: 22_400)`，然後以公開放置指令檢查它停在 B 的整列姿態。

**預期**：若契約是決策 287 所寫「列車停下來不會妨礙別條軌道」，就不能單以車頭所在點通過；應檢查從車頭向後、包含上一條邊的車身。

**實際（VERIFIED）**：接受 B 作分界（22,400 單位＝350 m，從初始車頭算）；車頭在 J 後 100 m，車尾仍在 J 前 140 m。`bodyStretches` 包含 e2 全段及 e1 的 87,040…96,000；既有 `foulingSpans` 列出 **6 筆** e4 span 妨礙，`WorldInvariants.violations` 仍是空的。

**驗證邊界**：這是直接驗證邊界器與合法停車姿態的反例；沒有把它推演成服務的多車死結，也沒有重現列車碰撞。預約仍可阻止別車進入。不能把它寫成已證明的高鐵一天死結。

**嚴重度**：P2，宣稱的清空條件不涵蓋長車通過道岔後等待的情形，岔線容量仍可能被車尾佔住。

**建議修法**：由作者在授權選停止點時按列車長度、行進方向與跨邊 trail 檢查停止後整列姿態，或設計保守的出口清空距離；保留上游接近道岔時的現有判斷。若決策其實只保證車頭，請作者明確縮小契約，並保留這個限制。

### R4：舊存檔的 invariant 檢查器本身中止

**位置**：`Tests/GameCoreTests/ReferenceVertical.swift:81` 的 `ReferenceWorld.carries(.automatic, …)` 明確 `preconditionFailure`，經 `NetworkInvariants` 由 `WorldInvariants` 呼叫。

**重現**：附錄 `testAllSaveFixturesRunOn`，指定 `REVIEW_FIXTURE=v28-terrain-track.json`；或用附錄的逐檔子程序腳本跑全部 67 份。這個測試在初始 invariant 檢查就中止。

**預期**：對合法、可載入的世界，檢查器回傳違規清單（此例應是空的），不直接殺掉整個測試程序。

**實際（VERIFIED）**：

```text
Fatal error: the reference model of decision 30 has no automatic structure
```

獨立程序退出 signal 4。**67/67 讀入並推進 60 分鐘成功、批次＝逐分；66/67 invariant 從初始到每分鐘均為空；v28 無法取得清單。** v28 也已在不呼叫該檢查器的獨立測試中成功推進。這是檢查器限制，不是證明 v28 存檔壞了。

**嚴重度**：P2（測試工具），阻止要求的全面舊檔 invariant 驗證，且會中止後續案例。

**建議修法**：交擁有 ReferenceWorld 的作者擴充自動結構／分段地形檢查；不要修改 v28、把 automatic 換成 surface 或跳過這份檔案來取得全綠。在支援前以子程序隔離，清楚保留未完成的驗證。

## 四、沒有找到新問題的項目，以及開關差異

### 四種開關：同一個小世界的實際結果

每格都是實跑，沒有只靠讀 caller 推論。F＝關、T＝開；開關順序為「行車控制／閉塞」。所有下列世界的批次與逐分結果相同；表中的「原場景」指附錄產生的同名 Support 所保留的建法。

| 小世界／推進時間 | F/F | F/T | T/F | T/T |
| --- | --- | --- | --- | --- |
| 原 Oncoming，兩列相向、40 條短邊，60 分 | 兩列到站 | 兩列到站 | 兩列到站 | 兩列到站 |
| 原 Terminus，X 出 A、Y 進 A，60 分 | Y 改 P2、X 到 B | 同左 | X 留 A、Y 留 B | X 留 A、Y 留 B |
| 原 ClearBlockBoundary，D／I，60 分 | 都到目的地 | 都到目的地 | D 到 T1，I 留 Y | 都到目的地 |
| 四站雙環軌、內外各一列，120 分 | 每列都停四站 | 同左 | 同左 | 同左 |

**差異如何解讀**：

- Terminus 的 T/F、T/T 是同一個「號誌關的回歸場景」開號誌後，X 與 Y 都沒完成班次；所以不能說 #816 的修正也涵蓋號誌開。原決策只要求號誌關。本次保留此反例供調度作者接手，**未列為 #816 新回歸**。若要擴大保證，需先從 `reservingDeparture`／避占用月台的入口分析，不是把 spacing 規則直接套在號誌開。
- ClearBlockBoundary 的 T/F 沒有閉塞，D 先到 T1 並停在那裡，I 仍在 Y；其完成順序與 T/T 不同。#822 沒有承諾關閉閉塞也改善這個場景；不把少一個到站斷言通過寫成新 bug。附錄探針刻意保留「兩車應到站」的失敗斷言，讓差異可見。
- 環線使用兩條各 8 邊的物理環軌，同四個站各有兩個月台，各一列內外環車，避免用不能會車的單線環去要求兩列迎面穿過。每車四站的 liveness 有檢查，不只比較兩個同樣卡住的世界。`ServiceLine` 不允許 ring 與 real runs 並存，這個環線場景不是宣稱直接跑到了 283 的 real-runs 分支。

### 其餘已跑、沒有找到反例的部分

- **67 份舊檔**：保留原世界規則，僅將時鐘設 `.normal` 讓它確實走；每份推進 60 個一分鐘 tick，與一次 `advance(ticks: 60)` 比整個 GameWorld。存讀檔 round trip 在能執行 invariant 的 66 份也通過。v28 的例外見 R4。
- **對頭／至少 20 km**：原 Oncoming 除了上述四種開關，逐秒掃描 3,600 秒沒有迎面同邊或車身重疊；每分鐘正規化速度後比較**整個世界**。另建 10 km／80 km 單線、每公里一條邊、兩端各有支線的 real-runs 小世界，各跑 120 分鐘；兩列都到站、分鐘採樣沒有同邊迎面，批次相同。80 km 案沒有逐秒檢查，不能宣稱排除所有短暫碰撞，也沒有證明任意路網都不死結。
- **暫停續跑**：Oncoming 每分鐘先暫停並 advance 77 ticks，再恢復；與未暫停世界相同。雙環與 ClearBlock 在第 13 分鐘暫停、存讀檔、恢復，各跑至 120／60 分鐘；與不中斷批次相同。
- **288 不重複、尚未誤點**：原測試與 R1 的前半確認已停過的前兩站不變、跳過 B 的到發均為折返時刻、回程及以後共同提前、各站 dwell 不變；正常一分鐘後已離 A。折返後、世界時刻 300 秒的存讀檔及續跑相同；立即存檔的反例另見 R2。
- **288 已誤點**：合法單次自排表，在到 A 前將 rate 設 0，超過原表回程 A 的到站 **406 秒**再恢復，於 **540 秒**折返；整張 timetable 不變（符合 `early <= 0` 的明文條件），沒有往後改表。開門時間窗過後存讀檔、再跑 120 分鐘，批次／逐分／載入續跑相同，invariant 空。
- **288 重複表**：同一張自排表，`timetablePeriod = 1200`，**240 秒**折返；整張表與 period 在折返當下及再跑 120 分鐘後都不變。不是只測期望保留的一個停靠。開門時間窗過後的存讀檔續跑、批次／逐分與 invariant 都通過。

## 五、測試本身的審查

沒有證據能判定作者刻意「為通過而寫」。新增測試確實檢查了選 P2、兩車到站、無迎面、分界被排除、I／D 解除互等，以及折返後時刻平移；本次原類別 **13 個測試全過**。

但有下列可具體補強的缺口（P3，測試覆蓋；建議交原作者，不另計為行車 bug）：

| 測試 | 現有侷限 | 建議檢查行為 |
| --- | --- | --- |
| 283 兩個 `testAMinuteInOneStepIsSixtyOneSecondSteps` | 只比 `trains`，沒有比整個世界 | 正規化 clock.speed 後比 GameWorld，包括 accounts、run dispatch、allowance；本次擴充未發現差異 |
| 287 `testNoBlockEndsWhereATrainFoulsTheRampOfATurnout` | 很有用，但只覆蓋朝岔線接近的分界；沒有長車通過後車尾仍壓住岔線 | 加 R3 的相反方向／長車、跨邊尾部，不能把 head clear 當 whole-train clear |
| 288 `testATrainTurnedShortLeavesAfterItsDwellNotWhenItWouldHaveComeBack` | 測時刻與「不再 waitingAtStop(3)」，沒有最後到站、行程／lateTrips 一致性；每次走一分鐘也錯過 R2 的時間窗 | 檢查真實終點、trip／tally，並在折返後秒級存讀檔；不能只用 execution 不是原值推論已正常完成 |
| `testTheThroughTrainTurnsBackShortAtTheSharedStation` 的註解 | 寫「save there loads」，方法實際只查 invariant／roundTrip；整分鐘已過開門時間 | 明列存檔相對折返的秒數；先前成功的整分鐘 round trip 不能代表第 1 秒也成功 |

附錄矩陣最初要求所有開關下兩車都到站，這個更強的假設在第四節所列三格失敗；沒有把期望改成較容易通過後，再宣稱原行車規則沒問題。另有建探針時誤用 edge 終點的 `stoppingAt`、未等到派車就讀 timetable、以分鐘採樣漏過已誤點折返狀態等測試設置錯誤，都已修正後重跑；不列產品發現。

## 六、驗證與接手

**VERIFIED（Linux，Swift 6.4.0）**：

- `.github/scripts/install-swift-linux.sh 6.4.0 /opt/swift`，官方簽章驗證通過。環境一般帳號不能寫 `/opt`，用 Docker 作為安裝執行器；實際 build/test 都在原 Linux workspace，用 `/opt/swift/usr/bin/swift`。
- `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；臨時探針與最終只留文件的版本分別建置。
- 原 `TerminusPlatformTests` 3、`OncomingTrainsTests` 2、`ClearBlockBoundaryTests` 3、`SharedSingleTrackTests` 5，合計 13，全部通過。
- 本文四種開關、環線、暫停／存讀檔、批次／逐分、逐秒對頭、10／80 km 單線、重複表、已誤點表，及 R1–R4 的實測結果如前；**失敗反例不是通過的測試**。
- 67 份 save 分別跑 60 分鐘；對 invariant 採逐檔子程序隔離：66 通過、v28 trap。沒有更動或跳過任何 fixture。
- `git diff --check`、`python3 -I tools/golden-checks/doc_numbers.py --check`、報告程式碼重建與檔案範圍檢查。

**UNVERIFIED**：完整 Swift suite／CI；新報告 PR 的 CI 結果另看該 PR checks。此次文件 PR 依現有規則可能不跑 Swift tier，不能用文件 gate 綠聲稱完整測試綠。macOS、iOS Simulator、實機、App 存檔排程實際踩到 R2、高鐵一整天與性能量測均未跑。R3 沒有端到端死結／碰撞證明。

**下一個人從哪裡接**：

1. #823 原作者先修 R1 的 effective schedule／trip log 整合；同時處理 R2 秒級存檔窗，沿用附錄反例作修正前紅燈，不改 fixture。
2. #822 原作者評估 R3 的整列停車清空契約與方向／車長；若只保證車頭，清楚記錄限制，不能把這個報告誤讀成已證明碰撞。
3. ReferenceWorld 作者補 R4 的 automatic 支援，再重跑全部 67 份 invariant；這一步完成前，全面 invariant 驗證仍有一份未完成。
4. 283 的號誌開終點站場景、關閉閉塞的 I 留 Y 行為，按第四節分析範圍與需求後再決定是否擴大規則。不要在本報告 PR 修核心。

本次報告與上述待修事項一起由 `docs/HANDOFF.md` §7.1 連結；只開 draft，不合併、不開 auto-merge、不推作者分支。

## 七、可直接重跑的 Linux 探針

以下程式碼是本次實跑的暫時測試，不是已修好的回歸測試。**不要直接加入 CI 後要求全綠**：R1、R2、R3 是失敗反例，R4 會使該程序 trap；矩陣的較強到站假設有第四節所述的失敗。測試檔不隨本 PR 提交。

先在審查基準或作者自己的修正分支，將下方 Swift block 存成 `Tests/GameCoreTests/PR816823ReviewProbeTests.swift`。為了重用原 PR 的小世界而不改原測試，產生一份暫時的 support 複本（只移除測試檔 helper 的 private，GameCore 一行都不改）：

```python
from pathlib import Path
root = Path('.')
parts = []
for old, new in [
    ('OncomingTrainsTests', 'ReviewOncomingSupport'),
    ('ClearBlockBoundaryTests', 'ReviewBlockSupport'),
    ('TerminusPlatformTests', 'ReviewTerminusSupport'),
    ('SharedSingleTrackTests', 'ReviewShortTurnSupport'),
    ('RingLineTests', 'ReviewRingSupport'),
]:
    source = (root / f'Tests/GameCoreTests/{old}.swift').read_text()
    parts.append(source.replace(old, new).replace('private ', ''))
(root / 'Tests/GameCoreTests/PR816823ReviewSupport.swift').write_text('\n'.join(parts))
```

```sh
export PATH=/opt/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
# 以方法名稱選測試，避免連同 Support 的原測試全部重複跑。
swift test --skip-build --filter PR816823ReviewProbeTests/testShortTurnAfterSaveAndLateTrips
swift test --skip-build --filter PR816823ReviewProbeTests/testSaveOneSecondAfterShortTurn
swift test --skip-build --filter PR816823ReviewProbeTests/testBlockHeadClearButTailFouls
# 只跑這個方法的程序會因既有檢查器中止；其餘 fixture 分開跑。
REVIEW_FIXTURE=v28-terrain-track.json swift test --skip-build --filter PR816823ReviewProbeTests/testAllSaveFixturesRunOn
swift test --skip-build --filter PR816823ReviewProbeTests/testAllSaveFixturesAdvanceOnly
swift test --skip-build --filter 'PR816823ReviewProbeTests/test(OncomingFourFlagsAndPauseBatch|TerminusFourFlagsAndBatch|RingFourFlagsAndSavePauseBatch|BlockFourFlagsAndPauseBatch|ShortTurnRepeatingAndAlreadyLate|LongSingleTrackLookahead)'
```

<!-- review-probe-swift-start -->
```swift
import Foundation
@testable import GameCore
import XCTest

final class PR816823ReviewProbeTests: XCTestCase {
    func testAllSaveFixturesRunOn() throws {
        let files = try FileManager.default.contentsOfDirectory(at: SavedGameTests.fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let selected = ProcessInfo.processInfo.environment["REVIEW_FIXTURE"]
        if selected == nil { XCTAssertEqual(files.count, 67) }
        for file in files where selected == nil || file.lastPathComponent == selected {
            FileHandle.standardError.write(Data("FIXTURE START \(file.lastPathComponent)\n".utf8))
            var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: file)).world
            world.setSpeed(.normal)
            XCTAssertEqual(WorldInvariants.violations(in: world), [], file.lastPathComponent)
            var batch = world
            for minute in 1...60 {
                try world.advance(ticks: 1)
                XCTAssertEqual(WorldInvariants.violations(in: world), [], "\(file.lastPathComponent) minute \(minute)")
            }
            try batch.advance(ticks: 60)
            XCTAssertTrue(batch == world, "fixture batch differs: \(file.lastPathComponent)")
            XCTAssertNil(WorldInvariants.roundTripProblem(of: world), file.lastPathComponent)
            print("FIXTURE END \(file.lastPathComponent)")
        }
    }

    func testAllSaveFixturesAdvanceOnly() throws {
        let files = try FileManager.default.contentsOfDirectory(at: SavedGameTests.fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let selected = ProcessInfo.processInfo.environment["REVIEW_FIXTURE"]
        if selected == nil { XCTAssertEqual(files.count, 67) }
        for file in files where selected == nil || file.lastPathComponent == selected {
            FileHandle.standardError.write(Data("FIXTURE START \(file.lastPathComponent)\n".utf8))
            var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: file)).world
            world.setSpeed(.normal)
            var batch = world
            for _ in 1...60 {
                try world.advance(ticks: 1)
            }
            try batch.advance(ticks: 60)
            XCTAssertTrue(batch == world, "fixture batch differs: \(file.lastPathComponent)")
            print("FIXTURE END \(file.lastPathComponent)")
        }
    }


    func testOncomingFourFlagsAndPauseBatch() throws {
        let helper = ReviewOncomingSupport(name: "support") { _ in }
        for traffic in [false, true] {
            for blocks in [false, true] {
                let scene = try helper.makeScene()
                var minute = scene.world
                try minute.setTrafficControl(traffic)
                minute.setBlockSections(blocks)
                var batch = minute
                try batch.advance(ticks: 60)
                var seconds = minute
                seconds.setSpeed(.x10)
                var meetings: [String] = []
                for _ in 0..<60 {
                    let before = minute
                    minute.setSpeed(.paused)
                    try minute.advance(ticks: 77)
                    minute.setSpeed(.normal)
                    XCTAssertTrue(before == minute, "pause flags \(traffic)/\(blocks)")
                    try minute.advance(ticks: 1)
                    for _ in 0..<60 {
                        try seconds.advance(ticks: 1)
                        if meetings.isEmpty { meetings = helper.meetings(in: seconds) }
                    }
                    var aligned = seconds
                    aligned.setSpeed(.normal)
                    XCTAssertTrue(minute == aligned, "seconds flags \(traffic)/\(blocks)")
                    XCTAssertEqual(WorldInvariants.violations(in: minute), [])
                }
                XCTAssertTrue(batch == minute, "batch flags \(traffic)/\(blocks)")
                XCTAssertEqual(meetings, [], "flags \(traffic)/\(blocks)")
                XCTAssertEqual(minute.stationsStoppedAt(by: scene.p), [scene.pEnd])
                XCTAssertEqual(minute.stationsStoppedAt(by: scene.q), [scene.qEnd])
                print("FLAGS oncoming \(traffic)/\(blocks) completed")
            }
        }
    }

    func testTerminusFourFlagsAndBatch() throws {
        let helper = ReviewTerminusSupport(name: "support") { _ in }
        for traffic in [false, true] {
            for blocks in [false, true] {
                let scene = try helper.makeScene()
                var minute = scene.world
                try minute.setTrafficControl(traffic)
                minute.setBlockSections(blocks)
                var batch = minute
                try batch.advance(ticks: 60)
                for _ in 0..<60 { try minute.advance(ticks: 1) }
                XCTAssertTrue(batch == minute, "terminus batch flags \(traffic)/\(blocks)")
                XCTAssertEqual(minute.stationsStoppedAt(by: scene.x), [scene.b], "terminus X \(traffic)/\(blocks)")
                XCTAssertEqual(minute.stationsStoppedAt(by: scene.y), [scene.a], "terminus Y \(traffic)/\(blocks)")
                XCTAssertEqual(WorldInvariants.violations(in: minute), [])
                print("FLAGS terminus \(traffic)/\(blocks) completed")
            }
        }
    }

    func testRingFourFlagsAndSavePauseBatch() throws {
        let helper = ReviewRingSupport(name: "support") { _ in }
        for traffic in [false, true] {
            for blocks in [false, true] {
                let original = try helper.makeLoopWorld()
                var world = try GameWorld(bounds: WorldBounds(width: 7_168, height: 12_000), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
                for copy in 0...1 {
                    let shift = Int64(copy * 6_000)
                    for node in original.network.nodes {
                        try world.buildTrackNode(at: WorldCoordinate(x: node.position.x, y: node.position.y + shift))
                    }
                    for edge in original.network.edges {
                        let curve: TrackCurve
                        if case .cubic(let p, let q) = edge.curve {
                            curve = .cubic(PlanPoint(x: p.x, y: p.y + shift), PlanPoint(x: q.x, y: q.y + shift))
                        } else { curve = .straight }
                        try world.buildTrackEdge(from: .node(edge.from.number + copy * 8), to: .node(edge.to.number + copy * 8), curve: curve)
                    }
                }
                for station in original.stations {
                    try world.buildStation(named: station.name, at: station.point)
                }
                for copy in 0...1 {
                    for p in original.network.platforms {
                        try world.addTrackPlatform(p.station, on: .edge(p.edge.number + copy * 8), from: p.start, to: p.end)
                    }
                }
                let line = try world.createLine(named: "ring", stops: [helper.alpha, helper.beta, helper.gamma, helper.delta]).id
                try world.setLineRing(line, to: true)
                try world.setLinePerformance(line, to: helper.crawl)
                try world.setLineServiceWindow(line, to: .allDay)
                try world.setLineTrainsInService(line, to: helper.pairs(2))
                for (edge, direction, offset) in [(1, TrackEdgeDirection.forward, Int64(1_024)), (9, .backward, Int64(512))] {
                    let id = try world.purchaseTrain(named: "T\(edge)").id
                    try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: direction), offset: offset))
                    if offset < 1_024 { try world.setTrainContinuation(id, along: [], stoppingAt: offset) }
                    try world.setTrainMovementRate(id, to: 1_024)
                    try world.assignTrain(id, to: line)
                }
                try world.setTrafficControl(traffic)
                world.setBlockSections(blocks)
                var batch = world
                try batch.advance(ticks: 120)
                var calls: [TrainID: Set<StationID>] = [:]
                for minute in 0..<120 {
                    if minute == 13 {
                        let before = world
                        world.setSpeed(.paused)
                        try world.advance(ticks: 100)
                        world = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
                        world.setSpeed(.normal)
                        XCTAssertTrue(world == before)
                    }
                    try world.advance(ticks: 1)
                    for t in world.trains { calls[t.id, default: []].formUnion(world.stationsStoppedAt(by: t.id)) }
                    XCTAssertEqual(WorldInvariants.violations(in: world), [])
                }
                XCTAssertTrue(world == batch, "ring batch \(traffic)/\(blocks)")
                for t in world.trains { XCTAssertEqual(calls[t.id]?.count, 4, "both ring trains must call at every station") }
                print("RING \(traffic)/\(blocks) calls \(calls)")
            }
        }
    }

    func testShortTurnAfterSaveAndLateTrips() throws {
        let helper = ReviewShortTurnSupport(name: "support") { _ in }
        var (world, _, through) = try helper.world()
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        world.setRealisticOperation(true)
        let line = try XCTUnwrap(world.assignedLine(of: through))
        var planned: [ScheduledStop] = []
        for _ in 0..<60 {
            if let t = world.train(id: through), !t.timetable.isEmpty, planned.isEmpty { planned = t.timetable }
            try world.advance(ticks: 1)
            if case .waitingAtStop(3, _)? = world.train(id: through)?.execution { break }
        }
        let turned = try XCTUnwrap(world.train(id: through))
        XCTAssertEqual(turned.execution, .waitingAtStop(3))
        print("TURN now=\(world.clock.now.seconds) planned=\(planned.map { $0.arrival.seconds }) actual=\(turned.timetable.map { $0.arrival.seconds }) trip=\(world.trips(of: through))")
        XCTAssertNotEqual(turned.timetable, planned)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertTrue(world == loaded)
        try world.setTrainMovementRate(through, to: 0)
        try loaded.setTrainMovementRate(through, to: 0)
        let release = turned.timetable.last!.arrival.seconds + 300
        while world.clock.now.seconds < release {
            try world.advance(ticks: 1)
            try loaded.advance(ticks: 1)
            XCTAssertTrue(world == loaded)
        }
        try world.setTrainMovementRate(through, to: 1_024)
        try loaded.setTrainMovementRate(through, to: 1_024)
        for _ in 0..<10 {
            try world.advance(ticks: 1)
            try loaded.advance(ticks: 1)
            XCTAssertTrue(world == loaded)
            if world.trips(of: through).first?.arrival != nil { break }
        }
        let trip = try XCTUnwrap(world.trips(of: through).first)
        let tally = world.lineDays(line).map(\.tally) + [world.lineAccounts?.records(of: line)?.pending ?? LineTally()]
        print("PUNCTUAL trip=\(trip) delay=\(String(describing: trip.delay)) late=\(String(describing: trip.isLate)) tally=\(tally)")
        XCTAssertNotNil(trip.arrival)
        XCTAssertEqual(trip.scheduledArrival, turned.timetable.last!.arrival, "trip log must use the shifted schedule too")
        XCTAssertEqual(tally.reduce(0) { $0 + $1.lateTrips }, trip.isLate == true ? 1 : 0, "the trip and tally must agree")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}

extension PR816823ReviewProbeTests {
    func testBlockHeadClearButTailFouls() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 200_000, height: 20_000), economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 97_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 103_424, y: 8_192))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 199_000, y: 8_192))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 103_424, y: 8_592))
        try world.buildTrackEdge(from: a, to: j) // e1 1.5 km
        try world.buildTrackEdge(from: j, to: b) // e2 100 m
        try world.buildTrackEdge(from: b, to: z) // e3
        try world.buildTrackEdge(from: j, to: c) // e4 diverges 1:16
        world.setBlockSections(true)
        try world.setTrafficControl(true)
        let id = try world.purchaseTrain(named: "long follower").id
        try world.setTrainCars(id, to: 16) // 240 m
        let f1 = TrackTraversal(edge: .edge(1), direction: .forward)
        let f2 = TrackTraversal(edge: .edge(2), direction: .forward)
        let f3 = TrackTraversal(edge: .edge(3), direction: .forward)
        try world.placeTrain(id, at: .onEdge(f1, offset: 80_000))
        try world.setTrainContinuation(id, along: [f2, f3], stoppingAt: 50_000)
        let envelope = world.authorityEnvelopes(of: try XCTUnwrap(world.train(id: id)))
        let boundary = world.blockBoundary(envelope, atOrBefore: 22_400)
        XCTAssertEqual(boundary, 22_400, "boundary at B is accepted")
        try world.unplaceTrain(id)
        try world.placeTrain(id, at: .onEdge(f2, offset: 6_400))
        // At the end of e2 the default empty continuation already stops here.
        let t = try XCTUnwrap(world.train(id: id))
        let fouled = world.resources(covering: world.bodyStretches(of: t)).flatMap { resource -> [TrackSpan] in
            if case .span(let span) = resource { return Array(world.network.foulingSpans[span] ?? []) }
            return []
        }.filter { $0.edge == .edge(4) }
        print("TAIL boundary=\(boundary) body=\(world.bodyStretches(of: t)) branchFouled=\(fouled.count)")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
        XCTAssertTrue(fouled.isEmpty, "a waiting train still fouls the branch behind its clear head")
    }

    func testShortTurnRepeatingAndAlreadyLate() throws {
        let helper = ReviewShortTurnSupport(name: "support") { _ in }
        for repeating in [false, true] {
            var sample = try helper.world().world
            try sample.advance(ticks: 2)
            let shuttlePlan = sample.trains[0].timetable
            let planned = sample.trains[1].timetable
            var (world, shuttle, through) = try helper.world()
            try world.unassignTrain(shuttle)
            try world.unassignTrain(through)
            for line in world.lines { try world.removeLine(line.id) }
            try world.setTrainTimetable(shuttle, to: shuttlePlan)
            try world.setTrainTimetable(through, to: planned, repeatingEvery: repeating ? 1_200 : nil)
            try world.startTrainService(shuttle)
            try world.startTrainService(through)
            // Reach the same deadlock as the line-generated world, then hold until past the return time.
            try world.advance(ticks: 2)
            print("SPECIAL setup repeat=\(repeating) planned=\(planned) executions=\(world.trains.map { String(describing: $0.execution) })")
            if !repeating {
                try world.setTrainMovementRate(through, to: 0)
                while world.clock.now <= planned[3].arrival { try world.advance(ticks: 1) }
                try world.setTrainMovementRate(through, to: 1_024)
            }
            var turnedAt: GameTime?
            world.setSpeed(.x10)
            for _ in 0..<1_800 {
                let before = world.clock.now
                try world.advance(ticks: 1)
                if case .waitingAtStop(3, _)? = world.train(id: through)?.execution { turnedAt = before; break }
            }
            print("SPECIAL before unwrap repeat=\(repeating) now=\(world.clock.now.seconds) executions=\(world.trains.map { String(describing: $0.execution) }) deadlock=\(world.deadlockedTrains())")
            let now = try XCTUnwrap(turnedAt)
            try world.advance(ticks: 8) // Test the unchanged schedule beyond the separately reported door-opening save bug.
            world.setSpeed(.normal)
            print("SPECIAL repeat=\(repeating) turnAt=\(now.seconds) scheduledBack=\(planned[3].arrival.seconds)")
            XCTAssertEqual(world.train(id: through)?.timetable, planned)
            XCTAssertEqual(world.train(id: through)?.timetablePeriod, repeating ? 1_200 : nil)
            if !repeating { XCTAssertGreaterThan(now, planned[3].arrival) }
            var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
            var batch = world
            try batch.advance(ticks: 120)
            for _ in 0..<120 {
                try world.advance(ticks: 1)
                try loaded.advance(ticks: 1)
                XCTAssertTrue(world == loaded)
                XCTAssertEqual(WorldInvariants.violations(in: world), [])
            }
            XCTAssertTrue(batch == world)
            XCTAssertEqual(world.train(id: through)?.timetable, planned)
        }
    }
}

extension PR816823ReviewProbeTests {
    func longSingleTrack(kilometres count: Int) throws -> (GameWorld, [TrainID], [StationID]) {
        let km: Int64 = 64_000
        var world = try GameWorld(bounds: WorldBounds(width: Int64(count + 5) * km, height: 20_000), economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(now: GameTime(minutes: 358), speed: .normal))
        let ps = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let qd = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 6_144))
        let j1 = try world.buildTrackNode(at: WorldCoordinate(x: 2 * km, y: 8_192))
        try world.buildTrackEdge(from: ps, to: j1)
        try world.buildTrackEdge(from: qd, to: j1)
        var node = j1
        for n in 1...count {
            let next = try world.buildTrackNode(at: WorldCoordinate(x: Int64(2 + n) * km, y: 8_192))
            try world.buildTrackEdge(from: node, to: next)
            node = next
        }
        let pd = try world.buildTrackNode(at: WorldCoordinate(x: Int64(count + 4) * km, y: 8_192))
        let qs = try world.buildTrackNode(at: WorldCoordinate(x: Int64(count + 4) * km, y: 10_240))
        try world.buildTrackEdge(from: node, to: pd)
        try world.buildTrackEdge(from: node, to: qs)
        func station(_ name: String, edge: Int, right: Bool) throws -> StationID {
            let id = try world.buildStation(named: name, at: PlanPoint(x: right ? Int64(count + 4) * km - 10_000 : 10_000, y: 14_000)).id
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.addTrackPlatform(id, on: .edge(edge), from: right ? length - 10_000 : 1_000, to: right ? length - 1_000 : 10_000)
            return id
        }
        let pStart = try station("PS", edge: 1, right: false)
        let qEnd = try station("QD", edge: 2, right: false)
        let pEnd = try station("PD", edge: count + 3, right: true)
        let qStart = try station("QS", edge: count + 4, right: true)
        var ids: [TrainID] = []
        for (name, stops, edge, direction) in [("P", [pStart, pEnd], 1, TrackEdgeDirection.forward), ("Q", [qStart, qEnd], count + 4, .backward)] {
            let line = try world.createLine(named: name, stops: stops).id
            try world.setLinePerformance(line, to: TrainPerformance(acceleration: 125, braking: 100, topSpeed: 320))
            try world.setLineRuns(line, to: [LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 21_600, departure: 21_600), LineRunTime(arrival: 25_200, departure: 25_200)])])
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: direction), offset: 10_000))
            try world.setTrainContinuation(id, along: [], stoppingAt: 10_000)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            ids.append(id)
        }
        return (world, ids, [pEnd, qEnd])
    }

    func testLongSingleTrackLookahead() throws {
        let helper = ReviewOncomingSupport(name: "support") { _ in }
        for km in [10, 80] {
            var (world, ids, ends) = try longSingleTrack(kilometres: km)
            var batch = world
            try batch.advance(ticks: 120)
            var firstMeeting: [String] = []
            for _ in 0..<120 {
                try world.advance(ticks: 1)
                if firstMeeting.isEmpty { firstMeeting = helper.meetings(in: world) }
            }
            print("LONG \(km) meeting=\(firstMeeting) positions=\(world.trains.map { String(describing: $0.position) }) executions=\(world.trains.map { String(describing: $0.execution) }) stops=\(ids.map { world.stationsStoppedAt(by: $0) })")
            XCTAssertTrue(batch == world)
            XCTAssertEqual(firstMeeting, [])
            for (id, end) in zip(ids, ends) { XCTAssertEqual(world.stationsStoppedAt(by: id), [end], "\(km) km") }
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
        }
    }
}

extension PR816823ReviewProbeTests {
    func testBlockFourFlagsAndPauseBatch() throws {
        let helper = ReviewBlockSupport(name: "support") { _ in }
        for traffic in [false, true] {
            for blocks in [false, true] {
                let scene = try helper.makeScene()
                var world = scene.world
                try world.setTrafficControl(traffic)
                world.setBlockSections(blocks)
                var batch = world
                try batch.advance(ticks: 60)
                for minute in 0..<60 {
                    if minute == 13 {
                        let before = world
                        world.setSpeed(.paused)
                        try world.advance(ticks: 123)
                        world = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
                        world.setSpeed(.normal)
                        XCTAssertTrue(world == before)
                    }
                    try world.advance(ticks: 1)
                    XCTAssertEqual(WorldInvariants.violations(in: world), [])
                }
                XCTAssertTrue(world == batch)
                XCTAssertEqual(world.stationsStoppedAt(by: scene.d), [scene.t1])
                XCTAssertEqual(world.stationsStoppedAt(by: scene.i), [scene.u])
                print("FLAGS block \(traffic)/\(blocks) completed")
            }
        }
    }
}

extension PR816823ReviewProbeTests {
    func testSaveOneSecondAfterShortTurn() throws {
        let helper = ReviewShortTurnSupport(name: "support") { _ in }
        var (world, _, through) = try helper.world()
        world.setSpeed(.x10)
        for _ in 0..<600 {
            try world.advance(ticks: 1)
            if case .waitingAtStop(3, _)? = world.train(id: through)?.execution { break }
        }
        let t = try XCTUnwrap(world.train(id: through))
        XCTAssertEqual(t.execution, .waitingAtStop(3))
        print("SAVE WINDOW now=\(world.clock.now.seconds) times=\(String(describing: t.times))")
        for secondsAfterTurn in [1, 7, 8] {
            var probe = world
            try probe.advance(ticks: secondsAfterTurn - 1)
            let data = try JSONEncoder().encode(SavedGame(world: probe))
            print("SAVE WINDOW after=\(secondsAfterTurn) now=\(probe.clock.now.seconds)")
            XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: data), "after \(secondsAfterTurn) seconds")
            XCTAssertNil(WorldInvariants.roundTripProblem(of: probe), "after \(secondsAfterTurn) seconds")
        }
    }
}
```
<!-- review-probe-swift-end -->

逐檔隔離 invariant（先執行上面的 build，這個 runner 路徑是本次 Swift 6.4 Linux 建置產物）：

```python
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess

repo = Path('.').resolve()
runner = repo / '.build/out/Products/Debug-linux-x86_64/GameCoreTests-test-runner'
logs = Path('/tmp/pr816-823-fixture-checks')
logs.mkdir(exist_ok=True)

def run(path):
    env = os.environ.copy()
    env['REVIEW_FIXTURE'] = path.name
    result = subprocess.run(
        [str(runner), 'GameCoreTests.PR816823ReviewProbeTests/testAllSaveFixturesRunOn'],
        cwd=repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    output = result.stdout.decode(errors='replace')
    (logs / (path.name + '.log')).write_text(output)
    return {'file': path.name, 'exit': result.returncode,
            'errors': [line for line in output.splitlines()
                       if 'error:' in line or 'Fatal error:' in line]}

with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, sorted((repo / 'SaveFixtures').glob('*.json'))))
print(json.dumps(results, ensure_ascii=False, indent=2))
print('passed', sum(row['exit'] == 0 for row in results), 'of', len(results))
```

本次輸出 66 of 67，唯一非零是 `v28-terrain-track.json`（signal 4）。測完移除兩個暫時的 `PR816823Review*.swift`，再重建確認最終文件 PR 不帶失敗測試；勿將本機輸出或 fixture 改寫回 repo。
