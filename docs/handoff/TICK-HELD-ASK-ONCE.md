# TICK-HELD-ASK-ONCE（2026-11-25）

## 進度

- 做到哪：**第 1 步做完，在 PR #2691**（繞路找不到之後，擋住它的那幾步沒放開就不重找；決策 980）。**第 2 步（見證車 Y 的快路）程式寫了約 120 行，但沒編譯、沒跑、沒提交**，不在 #2691 裡；內容與剩下的事見下面「第 2 步寫到哪」，差異檔在專案共用資料夾 `tick-held-ask-once/step2-witness-wip.diff`。接手的工作串（分支 `claude/project-thread-5bvsbq`）壓縮 2 次，照派工說明停手。
- 已驗證（只有第 1 步）：八個世界新舊 build 逐小時雜湊相同；稽核下機捷略過 200,470 次、香港 71,228 次、台灣（到 10 時）177,500 次找路，每次重找都確認找不到。同機成對量：機捷 233.1 → 198.9 ms／tick（−15 %）、香港 175.5 → 165.9（−5 %）、台灣 933.4 → 854.4（−8 %），寫實世界沒有差別。數字全表在決策 980。
- 下一步的第一個指令：從最新的 `main` 開分支，`git apply` 那份差異檔（拿不到就照「第 2 步寫到哪」重寫），`swift build --target GameCoreTests -Xswiftc -warnings-as-errors`；編過之後照該節「還要做的」依序做，第一件是稽核開著跑 `HeldDepartureMemoTests`。

## 派工

- 協調者派工：評分檔（私有庫 `a91453/railway-assets-private-2` `docs/priorities/TICK-ROUTING.md`）第 1 名，2.55。被擋住的列車每秒重問「能走了嗎」並重找繞路；改成記住被什麼擋，那個沒變就不重問、不重找。必須證明結果不變，防撞車的規則不能動到行為。
- 雲端工作串「讓被擋的列車不再每秒重問」，分支 `claude/project-thread-s6z3ac`（量測與做法，停手）；接手的是「完成被擋列車不再每秒重問」，分支 `claude/project-thread-5bvsbq`，決策 980（#2118 已登記）。
- 存檔版本、golden schema：不動。`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 不動。

## 量到什麼

量法：`BoughtWorldSaveTests` 與 `DepotReturnReportTests` 鋪世界，`SavedWorldTickReportTests` 逐 tick 跑（一 tick 一分鐘、裡面一步一秒），GameCore 裡臨時加計數（沒提交，見最後一節）。次數是硬的；時間是同時跑三四個程序時量的，只能看比例。

| 一天裡（台灣到 10 時，600 tick） | 機捷 `tymc-controlled` | 香港 `hk-all-simple` | 台灣 `taiwan-all-simple` |
|---|---:|---:|---:|
| 發車問（`departService` 裡的 `reservingDeparture`） | 198,803 | 57,286 | 137,752 |
| 　其中答案還是「被擋」 | 196,242（98.7 %） | 53,670（93.7 %） | 134,339（97.5 %） |
| 　和這列車上一次問的候選只差 `times` | 196,973 | 53,750 | 134,571 |
| 　候選不同／這列車第一次問 | 326／1,504 | 228／3,307 | 468／2,712 |
| 其他地方問（派車、死結、機廠） | 30,432（被擋 29,273） | 25,061（19,408） | 33,214（29,055） |
| 「幾秒後會放」的試走裡問（`secondsUntilARouteFrees`） | 12,295（12,140） | 8,231（7,970） | 1,833（1,771） |
| 「該輪到誰」裡問（`turnOwedFor`） | 2,108（2,028） | 730（708） | 1,684（1,462） |
| 問答合計占整個執行時間 | 約 36 % | 約 15 % | 約 27 % |

被擋之後，`takingAnyDeparture` 走到哪一步（含上面所有來源；三個世界都沒有「列了月台清單」的發車，也都沒開閉塞）：

| | 機捷 | 香港 | 台灣 |
|---|---:|---:|---:|
| 預設路被擋（`planned` 是 `.held`） | 239,945 | 82,864 | 166,893 |
| 　擋的車占著軌道、站著（跟不了） | 115,066 | 33,439 | 99,308 |
| 　擋的車占著軌道、在動（但不能跟） | 118,841 | 46,826 | 57,883 |
| 　擋的車只是在等那段（claim）、在動 | 8,588 | 1,774 | 5,257 |
| 　沒有可跟的距離／會逆線停 | 3,472／101 | 2,625／0 | 6,322／50 |
| 繞路第一次找路（不看別人方向）：找不到 | 223,350 | 73,954 | 159,911 |
| 　找得到 | 20,849 | 9,444 | 9,884 |
| 　　其中逆著別人的方向，第二次找路也找不到 | 20,127 | 8,337 | 9,515 |
| 繞路成功 | 261 | 1,099 | 257 |
| 繞過站著的車成功（`takingFreeBerthPastStandingTrain`） | 1 | 9 | 9 |

時間怎麼分（巢狀計時，機捷）：預設路那一問 70 秒、繞路（含建 `blockedTrack`）75 秒（第一次找路找不到占 52 秒）、繞過站著的車 30 秒（它最後也是同一個找路再做一次）。台灣的繞路 89 秒裡找路只有約 43 秒，其餘推算是每次重建 `blockedTrack(except:holders:)`（150 列車時不便宜），所以檢查見證時不要先把它建出來。

結論：**被擋的發車幾乎每秒都拿同一個候選（只差 `times`）再問一次，九成以上答案沒變；每問一次做一次預設路判斷、一到兩次整張找路。** 派工單寫的「一天 1,500 班問近 20 萬次」對得上（198,803）。

順帶量到、屬於別張單的：試走裡的 `canExtendAnyAuthority` 與 `moveTrains`（機捷 49,721 次 59 秒＋53,057 次 25 秒；香港 33,485 次 63 秒＋43,109 次 38 秒），那是 TICK-HOLDERS-BY-CLAIM／TICK-FREES-FROM-HOLDERS 的範圍，這張單省不到。

### 基準（`main`，沒改過的 build，一次只跑一個）

| 世界 | 站／線／列車 | tick | 平均每 tick | 中位數 | p95 | 總雜湊（`checksums`） | 最後一個 | 死結 |
|---|---|---:|---:|---:|---:|---|---|---|
| `tymc-controlled` | 24／1／32 | 1,440 | 346.6 ms | 365.8 ms | 720.0 ms | `78cfde4da92b515a` | `1002374431502cc8`（第 1 天 00:00） | 最多 7 列（17:17，4 個 tick） |
| `hk-all-simple` | 22／6／36 | 1,440 | 246.3 ms | 226.3 ms | 623.9 ms | `aa99802671e30ac7` | `b9e9a1f90868c30`（第 1 天 00:00） | 無 |
| `taiwan-all-simple` | 161／15／150 | 600 | 1,090.4 ms | 198.9 ms | 3,584.9 ms | `e57b9af7dea419d8` | `deb27fa19be496`（第 0 天 10:00） | 無 |

三個都是「交通管制開、閉塞關」。這台雲端機器比評分檔那次慢（評分檔：香港 167、機捷 231、台灣 739 ms），所以前後耗時一定要在同一台機器上重量，不能拿這張表當「改前」。加了臨時計數的 build 三個世界的雜湊都和這張表相同。

每小時的雜湊（時 雜湊；找第一個不同的小時用）：

```text
tymc-controlled
01 b848fac555575191  02 b2056a5dd613d248  03 c6e6d2d55d507ac2  04 c40b4c04774174d7
05 c9c2312bb3acd32f  06 50a7440e83d4410a  07 a8f51aae92106613  08 207975f29fdaac0b
09 fa249b745dc2ffff  10 d6de431462fecfbc  11 d22ec9a7c4eb6117  12 c7b0b154a3c1daee
13 57d10a8376ae6212  14 cbc5d0b55d9cd97b  15 fdd52325fcc9561b  16 8d77ff59e05a94b6
17 909f45e15dec0f00  18 9c037749c4791379  19 c6533ebe26e596b7  20 f319860cbe22ae59
21 edb53065403f3fd0  22 1fd9aa5b3a16ea1c  23 b849ec7e27745211  24 1002374431502cc8
hk-all-simple
01 1b0f474f0b7bf327  02 5289f2aa96c6eeb1  03 56b0ca6b5720391c  04 3988444a84ac99
05 c7a414b20865752a  06 d76506f7096a5719  07 c0234db40d54cbee  08 f837d3bd6a3d836c
09 9c202a6db39c128e  10 df3e424767783b4f  11 6a63d5aea01d48db  12 88e91ef0664b518c
13 926f8e63fcad573c  14 2f47535032372f65  15 c356f660c6a050cb  16 1ae81132490163c2
17 9a44cfdbec5a5cb0  18 295bb38cdf733fb3  19 bec0a232dc8acc5d  20 cab02959caa42adb
21 f019156de3fcdf4a  22 28376f3499c299fd  23 f4ba4ee12b5d4fea  24 b9e9a1f90868c30
taiwan-all-simple
01 475d03b2e4a52e0f  02 96ef56d41d1db6c8  03 aa29645af143cfbf  04 3975b72acaf568e
05 218f7c480741555c  06 e401bfb4db3da85d  07 50126ae6ccdd7190  08 478f7d30ab8c425f
09 5e63db93a977c34c  10 deb27fa19be496
```

存檔是在 `e5eac2f` 鋪的，照當時 `main` 的鋪法，鋪線規則一變雜湊就不同，新舊 build 一定要用同一份存檔比。

## 做法（第 3 點已寫，其餘還沒寫）：被擋的答案連同「靠什麼成立」一起記

誰用得到：只需要「被擋還是可走」、不用擋的是誰的呼叫處。整個 GameCore 只有兩處讀 `.held(by:)` 的車號：`RouteReservation.swift:174`（只在有月台清單時）與 `GameWorld.swift:2629`（手動指令，走 `reserving`，不走這條）。其餘（`WorldDeparture.swift:121`、`WorldDispatch.swift:553`、`WorldMovement.swift:522`、`FairSingleTrack.swift:123`、`Deadlock.swift:99` 與派車、機廠那十幾處）都只比 `case .held`／`case .granted`。所以加一個只回答「還是被擋嗎」的快路，`takingDeparture`／`reservingDeparture` 本身的語意一個字不動：快路說「是」就當被擋，說「不知道」就照舊完整算一次，算出被擋時順手記下見證。

一筆紀錄（放 `DirectionMemo`，例如 `heldDepartures: [TrainID: HeldDeparture]`）成立的條件：

1. **候選相同**：問的候選把 `times` 換成紀錄裡的之後與紀錄的候選相等（`Train` 是 `Equatable`）。被證明的那幾步都不讀 `times`（要確認 `routeStretches(of:)`、`listedDepartures(of:memo:)` 真的不讀；稽核會抓）。
2. **預設路仍被擋、仍不能跟（見證車 Y）**：紀錄一列車 Y。現在的世界裡 Y 還在路網上、仍占著或侵到候選的 envelope（`TrackHolders.holding(envelope, except:, fouling: true, in:)` 在 Y 那一格為真；只問 Y 一列就是 `firstHolding(envelope, except: 候選, among: [Y], fouling: true, in:) != nil`），而且 `isLeading(Y, onto: envelope, for: 候選)` 現算為假。
   - 為什麼夠：`reserving(_:following:memo:)`（`RouteNeeds.swift:27`）在 `holder(of: envelope…) != nil` 時只有 `followingAuthority` 給得出車才 `.granted`；`followingAuthority`（`RouteFollowing.swift:317`）對每一列「占著或等著這段」的車都要 `isLeading`，有一列不是就回 `nil`。Y 占著 ⇒ 有 holder；Y 不領頭 ⇒ 不能跟 ⇒ `.held`。
   - Y 站著（不是 `.travellingToStop` 或 `movement.rate == 0`）時 `isLeading` 第一行就假，最便宜；在動的 Y 要現算（讀 Y 的路與候選的路，沒有全域的東西）。
   - 不記的情況：被擋是因為「沒有可跟的距離」「會逆線停」、或擋的只是 claim（等著那段、還沒占）。這些照舊完整算（合計約 5 %）。
   - 開閉塞時前面還有兩步：決策 562 的 `followerCutOff` 只會多出「被擋」，不影響；決策 294 的 `reservingApproach` 分支走不走只看候選、路網與路線（同一個候選不會變），紀錄只在「沒走這個分支」時寫。
3. **繞路仍找不到（見證集合 B）**：第一次找路（`alternativeRoute` 裡不看別人方向的 `path(from:toStation:length:avoiding:)`）回 `nil` 時，記下找路過程中 `clear` 回答「不通」的每一段 `TrackStretch`（集合 B）。現在的世界裡 B 的每一段仍被擋（`blocked.blocks(cover(of: [段]), in: network)`）就仍是 `nil`。
   - 為什麼夠：`TrainRoute.shortest`（`TrainRoute.swift:74`）沒找到終點時不剪枝，可達的每個地方都會彈出、對每一步問過 `allowed(to:)`（`ServicePath.swift:232` 的 `networkPath`）。新世界的找路從同一個起點出發；歸納：它走得到的地方舊的也走得到，因為它要走的每一步舊的都問過，舊的說不通的在 B 裡、現在仍不通。舊的到不了任何月台，新的也到不了。`allowed` 其餘的條件（`forbidden`、機廠側線、封閉中的軌道）在一次 `advance` 裡不變。
   - 同一個 `nil` 也蓋掉 `takingFreeBerthPastStandingTrain`（`RouteNeeds.swift:362`）：它最後一關是 `counterflowRoute`，同樣的起點、車站、車長、`blockedTrack(except: 候選)`，就是同一次找路。
   - `BlockedTrack.blocks` 第一行是「有車直接占著就擋」；檢查 B 時先用 holders 直接問，只有某一段不是被直接占著時才去建 `blockedTrack`（台灣那 40 多秒就省在這）。
   - 需要 `path(from:toStation:length:avoiding:)` 的一個會把「不通的段」交出來的版本（`clear` 包一層就好，結果不變）。
4. **開閉塞時的最後一段**（`standingBlocked`）：現算 `standing` 與 `standingBlocked`；`!standingBlocked.blocks(envelope)` 就是被擋，否則要第二次找路自己的見證集合 B′ 仍成立。三個簡單世界走不到這裡，寫實世界（`*-realistic`）才會。

v1 不管、照舊完整算的：

- 第一次找路**找得到**路的（機捷約 9 %：找得到 → 逆著別人的方向 → 第二次找路找不到）。第二次找路的 `forbids` 來自 `opposingParts`（讀每一列別的車的方向，每秒在變），沒有便宜的見證。
- 有月台清單的發車（三個世界都是 0 次；要做的話每個清單項各記一個見證車）。
- 「可走，但該輪到別人」（`turnOwed`）：快路只回答 `takingDeparture` 是不是 `.held`，可走的照舊。

估計（沒驗證）：機捷被擋的問大約 86 % 命中（約 95 % 有占著的見證車 × 約 91 % 第一次找路找不到），一次檢查幾十微秒對現在一次完整問約 0.5–0.7 毫秒，機捷每 tick 大約少四分之一；香港問答只占 15 %，省得少；台灣介於中間。

## 怎麼證明結果不變

- **稽核**：照 `AnswerAudit`（`ServiceDirections.swift:226`，`@TaskLocal static var answerAudit`）加一個。快路每命中一次，稽核開著時就把完整的 `takingDeparture` 再算一次，`precondition` 它是 `.held`，並計數；接進 `SavedWorldTickReportTests` 的 `SAVED_WORLD_AUDIT=1`（那行 `SAVED_WORLD audit:` 加上次數），另加一個 GameCore 測試（照 `AnswerAuditTests`）。
- **雜湊**：六個世界（香港、羅瓦涅米、台灣各簡單與寫實）加機捷兩個，新舊 build 的整點雜湊逐行相同。寫實世界一定要跑，閉塞那幾個分支只有它們走得到。
- **時間**：新舊 build 各複製到一個目錄，同一台機器、一次只跑一個，報平均每 tick。

## 怎麼量（工具都在 repo；`/tmp/worlds` 換成自己的目錄）

```sh
# 1. 六個全買世界（GamePresentation，約 5–15 分鐘）
BOUGHT_WORLDS=/tmp/worlds swift test --skip-build --filter BoughtWorldSaveTests
# 2. 機捷一條線，第 0 天 00:00 存檔（十幾秒；拿掉 SIMPLE 與 CONTROLLED 就是寫實版，檔名自己換）
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=tymc DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 \
  DEPOT_RETURN_SAVE=/tmp/worlds/tymc-controlled.json DEPOT_RETURN_SAVE_AT=0 DEPOT_RETURN_UNTIL=1 \
  swift test --skip-build --filter DepotReturnReportTests/testTheTaoyuanAirportLine
# 3. 一天的時間與整點雜湊（台灣加 SAVED_WORLD_TICKS=600，到 10 時）
SAVED_WORLD=/tmp/worlds/tymc-controlled.json SAVED_WORLD_EACH=1 SAVED_WORLD_HOURS=1 \
  swift test --skip-build --filter SavedWorldTickReportTests
```

- 改 GameCore 後 `swift build --target GameCoreTests -Xswiftc -warnings-as-errors` 約 4–5 分鐘（`--target` 與 `--build-tests` 不能同時給；整包 `--build-tests` 約 13 分鐘）。
- 比兩個 build：把 `.build/debug/GameCoreTests-test-runner` 與 `GameCoreTests.so` 複製到各自的目錄，跑 `<目錄>/GameCoreTests-test-runner GameCoreTests.SavedWorldTickReportTests/testWhatASavedWorldCostsATick`，`diff` 兩邊的 `checksum` 行（`docs/handoff/TICK-REAL.md`「怎麼量」）。

## 下一步（依序，每一步後都比雜湊）

1. **（已做，決策 980）半步：只記繞路找不到（上面第 3 點）。** 實際做法與結果見下面「第 1 步做了什麼」。原來的說明： 評分檔也建議先做這半步，風險最低：`planned` 照舊每次算，被擋時先看紀錄的 B 是否仍成立，成立就跳過 `alternativeRoute` 與 `takingFreeBerthPastStandingTrain`，直接回 `planned`（這半步連擋的車號都和原來一樣，所以可以直接放進 `takingAnyDeparture`，所有呼叫處都受益）。估計（沒驗證）機捷可省問答時間的一半上下。配稽核。
2. **（程式寫了，沒編譯、沒驗證；見「第 2 步寫到哪」）整步：加見證車 Y（第 2 點）的快路。** 做法比原計畫簡單：快路回的車號現算，和完整路徑逐字相同，所以直接放進 `takingAnyDeparture`，不用一處一處接呼叫處。原來的說明：接到只比 `.held`／`.granted` 的呼叫處，先接 `departService`（最大宗），再接試走、`turnOwedFor`、`Deadlock.swift:99` 與派車那幾處。每接一處比一次雜湊。
3. 寫實世界的第 4 點；跑寫實的雜湊與稽核。
4. 決策 980 已寫（第 1 步）；第 2、3 步各在同一個檔加一段「**後來**」（做了什麼、為什麼結果一樣、新舊雜湊與時間），不另取編號。PR 裡附「找過什麼」（參考庫與外部專案都沒有可搬的：這是這個專案自己的保留規則上的備忘）。
5. 之後可再做、不在這張單：紀錄跨 `advance` 借用（照 `RouteMemo.Key` 的 `lend`／`keep`）；第一次找路找得到的那 9 %。

## 第 1 步做了什麼（2026-11-25，決策 980）

- `ServicePath.swift`：`path(from:toStation:length:avoiding:refused:)`，原來的找路多交出「因為 `blocked` 不能走的每一步」（各自的 `TrackCover`）。
- `ServiceDirections.swift`：`DirectionMemo.NoDetour` 與 `noDetours: [TrainID: NoDetour]`；`AnswerAudit` 多 `detoursNotSearched`、`detoursSearched`。
- `RouteNeeds.swift`：`alternativeRoute(…keepingNoWay:…)`（只有 `takingAnyDeparture` 第一個呼叫處傳 `true`，第一次找路找不到就寫紀錄）；`stillHasNoDetour(_:to:memo:)`（先用 holders 直接問每一步有沒有車占著，沒有才建 `blockedTrack` 問 `blocksUnheld`；稽核開著時把找路照做一遍）；`takingAnyDeparture` 在紀錄成立時跳過 `alternativeRoute` 與 `takingFreeBerthPastStandingTrain`。`planned` 照舊每次算。`BlockedTrack.blocks` 拆出 `blocksUnheld`（沒有車直接占著時問的那一半）。
- 測試：`HeldDepartureMemoTests`（帶著走的備忘對全新的備忘，兩個世界）；`SavedWorldTickReportTests` 的稽核那一行多印兩個次數。
- 量到的：略過率（略過／被擋後進到繞路這一步的次數）機捷 83 %、香港 79 %、台灣 89 %；羅瓦涅米 0（被擋的很少，而且第一次找路都找得到）。時間：機捷 −15 %、香港 −5 %、台灣 −8 %，寫實世界沒有差別（±2 %，雜訊內；寫實的略過次數：機捷 27,686、香港 40,761、台灣到 10 時 38,587）。**比原來估的少**：原估「機捷可省問答時間的一半上下」，實際機捷省 15 %；台灣略過近九成卻只省 8 %，表示那裡貴的不是找路本身。
- 給第 2 步的提醒（這條工作串讀程式時確認的）：
  - `isLeading(_:onto:for:)` 每次都重算跟車者的 `ways`（`bodyStretches + routeStretches` 的 traversal 集合）；快路可以把候選的 envelope 與 `ways` 一起記在紀錄裡，另開一個吃現成 `ways` 的 `isLeading`。
  - 快路要回的 `.held(by:)` 車號可以現算：`holder(of: 記下的 envelope, except: 候選, holders:)`，和完整路徑第一步是同一個呼叫，所以回傳值與原來逐字相同，呼叫處都不用改（不必像原計畫只接「只比 `.held`／`.granted`」的呼叫處）。
  - 見證車要在「要寫紀錄的那一次」另外找（`holders.holding(envelope, except:, fouling: true, in:)` 為真而且 `isLeading` 為假的第一列），因為 `followingAuthority` 在第一列不領頭的車就回 `nil`，那一列可能只是在等（claim），不能當見證。只在 `noDetours` 已有這列車的紀錄時才值得找。
  - `train(id:)` 是從頭掃；見證車記它在 `trains` 裡的位置，用 `trains[place].id == Y` 驗。

## 第 2 步寫到哪（2026-11-25；沒編譯、沒跑、沒提交）

差異檔 `step2-witness-wip.diff`（183 行，對 `af1a2f6`，也就是 #2691 的 GameCore，`git apply`）在專案共用資料夾 `tick-held-ask-once/`。它只動三個檔，不開閉塞時才生效：

- `RouteFollowing.swift`：`isLeading(_:onto:for:)` 拆成三個：原來的簽名改呼叫 `isLeading(_:onto:followerWays:)`（跟車者的 traversal 集合用 `@autoclosure` 傳，前面的 guard 過了才算），加 `ways(of:)`。行為不變。
- `ServiceDirections.swift`：`DirectionMemo.HeldDeparture`（`candidate`、`station`、`envelope`、`ways`、見證車在 `trains` 裡的位置 `witness` 與 `witnessID`）與 `heldDepartures: [TrainID: HeldDeparture]`；`AnswerAudit.heldNotAsked`。
- `RouteNeeds.swift`：原來的 `takingAnyDeparture` 本體改名 `askingAnyDeparture`；新的 `takingAnyDeparture` 先問 `stillHolder(of:memo:)`，有答案就回 `.held(by:)`（稽核開著時計數，並 `precondition` `askingAnyDeparture` 回的是同一個 `.held(by:)`），沒有就照舊問。`askingAnyDeparture` 在 `guard blockSections else { … return planned }` 那裡（被擋、繞路也沒有）呼叫 `keepHeld(_:to:memo:)` 寫紀錄。

```swift
func stillHolder(of candidate: Train, memo: inout DirectionMemo) -> TrainID? {
    guard isTrafficControlEnabled, !blockSections, let known = memo.heldDepartures[candidate.id] else { return nil }
    var asked = candidate
    asked.times = known.candidate.times
    guard asked == known.candidate, trains.indices.contains(known.witness) else { return nil }
    let witness = trains[known.witness]
    guard witness.id == known.witnessID, witness.position != nil else { return nil }
    let holders = trackHolders(memo: &memo)
    guard let holder = holder(of: known.envelope, except: candidate.id, holders: holders),
          holders.firstHolding(known.envelope, except: candidate.id, among: [known.witnessID], fouling: true, in: network) != nil,
          !isLeading(witness, onto: known.envelope, followerWays: known.ways),
          stillHasNoDetour(candidate, to: known.station, memo: &memo)
    else { return nil }
    return holder
}

func keepHeld(_ candidate: Train, to station: StationID, memo: inout DirectionMemo) {
    memo.heldDepartures[candidate.id] = nil
    guard let known = memo.noDetours[candidate.id], known.start == candidate.position,
          known.station == station, known.length == candidate.length
    else { return }
    let route = routeStretches(of: candidate)
    guard route.moves else { return }
    let stretches = bodyStretches(of: candidate) + route.stretches
    let envelope = cover(of: stretches)
    let ways = Set(stretches.map(\.traversal))
    let holding = trackHolders(memo: &memo).holding(envelope, except: candidate.id, fouling: true, in: network)
    func isStanding(_ train: Train) -> Bool {
        guard case .travellingToStop? = train.execution, train.movement.rate > 0 else { return true }
        return false
    }
    let inTheWay = trains.indices.filter { holding[$0] && trains[$0].id != candidate.id && trains[$0].position != nil }
    guard let witness = inTheWay.first(where: { isStanding(trains[$0]) })
        ?? inTheWay.first(where: { !isLeading(trains[$0], onto: envelope, followerWays: ways) })
    else { return }
    memo.heldDepartures[candidate.id] = DirectionMemo.HeldDeparture(
        candidate: candidate, station: station, envelope: envelope, ways: ways, witness: witness, witnessID: trains[witness].id)
}
```

寫的時候對過、但沒跑過的地方（編過之後先懷疑這幾處）：

- envelope 的算法和 `reserving(_:following:memo:)` 不開閉塞時那一行相同（`cover(of: bodyStretches + route.stretches)`），`holder(of:except:holders:)` 也是同一個呼叫，所以車號應該相同；稽核會逐次比。
- `holding(…)` 回的是不是「每列車一格」的布林陣列、`firstHolding(… among:)` 的參數型別，只憑第 1 步用過的樣子寫的，編譯會說。
- 「侵到（fouling）但沒占著」的車能不能當見證：要確認 `followingAuthority` 也會問到它的 `isLeading`（做法第 2 點是前一條工作串讀程式後寫的 `fouling: true`）。不確定就把 `keepHeld` 與 `stillHolder` 都改成 `fouling: false`，命中少一點但推論更短。
- 有月台清單的發車、`turnOwed`：都在 `takingAnyDeparture` 外面（`takingDeparture`），沒動；要確認 `takingAnyDeparture` 沒有別的呼叫處期待它每次都把 `planned` 算過（它順手填的備忘只是快取）。
- 稽核那一次 `askingAnyDeparture` 會再呼叫 `keepHeld` 重寫同一筆紀錄，不影響答案。

還要做的（依序）：

1. 編譯；`HeldDepartureMemoTests` 加 `XCTAssertGreaterThan(audit.heldNotAsked, …)`（先印出兩個世界各命中幾次再定門檻），`SavedWorldTickReportTests` 的 `SAVED_WORLD audit:` 那行多印 `heldNotAsked`。
2. 八個世界新舊雜湊（舊的用 #2691 合併後的 `main`；各世界的雜湊總和在決策 980 的表裡，第 2 步做對了不會變），再跑稽核（`SAVED_WORLD_AUDIT=1`），再成對量時間。
3. 命中率低就看 `keepHeld` 找不到見證的原因（擋的只是 claim、可以跟但沒距離）；第 1 步之後 `planned` 那一問還剩多少時間先量一下再決定值不值得（台灣第 1 步略過近九成找路只省 8 %，貴的可能已經不在這條路上，而在「誰占哪一段」的重建：那是評分檔的 TICK-HOLDERS-BY-CLAIM）。**如果量出來省不到 3 %，就不要合，在決策 980 記一筆「量過不值得」然後收單。**
4. 決策 980 加「**後來**」一段；開第二張 PR；#2118 留言。

## 要小心的

- **holders 的新舊**：`docs/handoff/TICK-REAL.md`「要小心的」寫過：不要預先把 holders 算熱、派車與步進的 holders 不要合。快路第一件事就是 `trackHolders(memo:)`，和完整路徑第一次用到它的位置相同（`reserving` 在沒開閉塞時第一行就取；被擋後 `takingAnyDeparture` 一定會再取），決策 877 之後 `keptHolders` 會在時刻不同時重排 claim，所以推論是 `memo.holders`／`holderChanges` 會和完整算時一樣。**這一點只是推論，沒跑過**；雜湊不同時先懷疑這裡。
- 快路跳過的其他備忘（`memo.paths`、`opposingParts` 等）都只是快取，少填不影響答案；但若有哪個備忘的「先填的人」會影響後來的答案，雜湊會抓到。
- 紀錄只在同一次 `advance` 的 `DirectionMemo` 裡有效（路網、設定、路線在裡面不變）。試走（`secondsUntilARouteFrees` 的 `frees`）是把世界複製後往前走幾秒再問，見證都是對「現在這個世界」現算的，所以同一筆紀錄拿去試走的世界問也成立；但要先看 `frees` 用的是哪一個 memo，紀錄寫不寫得回去。
- `isLeading` 讀 `blockSections || !isFollowing(train) || holdsToItsApproach(train)`，都要對現在的世界現算，不能記。
- 候選比對用「除了 `times` 之外相等」；若之後 `Train` 多了每秒會變的欄位，命中率會掉到零（不會錯，只是白做），用計數看得出來。
- `GoldenScenarios/`、`ReplayFixtures/` 是行為契約：這張單做對了它們不會動，動了就是做錯。

## 臨時計數怎麼加（沒提交）

`enum HeldProbe`（`nonisolated(unsafe) static` 的計數陣列與字典，`clock_gettime(CLOCK_MONOTONIC)` 計時），在 `takingDeparture` 外面包一層記「誰問的」（`departService` 設 1、`goOn` 2、試走 3、`turnOwedFor` 4、其餘 0），在 `takingAnyDeparture`、`alternativeRoute`、`reserving`、`followingAuthority` 的每個出口記一筆，`SavedWorldTickReportTests` 結束時印出。探針 build 的雜湊與沒改的 build 相同。原檔與三個世界的輸出放在專案共用資料夾 `tick-held-ask-once/`（`held-probe.diff` 可對 `e5eac2f` 的 GameCore `git apply`）；不在這個專案裡的人照這段重加即可，約 280 行。

## UNVERIFIED

- 第 1 步以外的做法（見證車 Y、開閉塞的最後一段）：第 2 步寫了沒跑，第 3 步沒寫。「估計少四分之一」是從次數與巢狀計時推的，第 1 步實際量到的比估的少（機捷 −15 %）。
- 上面「時間怎麼分」是多個程序同時跑時量的；基準表是一次只跑一個、雲端 Linux 4 核，換機器只能看相對。
- 寫實（開閉塞）世界沒量問答次數，只有存檔。
