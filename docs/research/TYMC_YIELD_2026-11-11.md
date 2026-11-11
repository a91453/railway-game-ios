# 機捷讓路的空車：為什麼舊線不動少 6 班、為什麼連讓（TYMC-YIELD，2026-11-11）

派工單 TYMC-YIELD（session_01YGNNupyS1CVXKpxSqb1jsv，遊戲規劃第 60 任派，第 61 任接），分支 `claude/tymc-yield-681`，決策 681。接 [HEALTH-124](HEALTH_124_2026-11-11.md) 第 6 節第 1、2 項。

**結論：原因查到了，沒有修成。GameCore 沒有改。** 試了 20 種寫法，沒有一種同時過三個機捷世界的門檻；而且查到決策 666 修好「下午環北↔機場第一航廈」靠的是一個副作用，和「舊線不動」傍晚少的 6 班是同一批讓路造成的，兩邊互相牴觸。這份記下證實的原因、每種寫法的數字，和建議的下一步。進 PR 的只有量測工具（`DepotReturnReportTests` 多一段讓路次數與最長連讓）與文件。存檔版本、golden schema、GoldenScenarios、SaveFixtures、ReplayFixtures 都沒動。

## 量法

Linux 雲端容器（4 核），Swift 6.4.0，debug（GameCore -O），main a714b812。簡單＋行車控制（新局預設）、最高倍速（十分鐘一格）、`DepotReturnReportTests`，和 HEALTH-124 第 4 節同一條指令（那邊是 release；沒發的班逐班相同）。讓路次數用 GameCore 裡暫時的探針數（每次 `depotBoundMakingWay` 回傳時印一行，已拿掉），所以最高倍速下也是確實的次數；「最長連讓」是同一列車從上一次讓到的站、30 分鐘內再讓的次數。（`DepotReturnReportTests` 印的「最長連讓」沒有 30 分鐘的時間窗：同一列車連續讓路，中間載客或進機廠才歸零。這份的數字兩種算法相同（機捷 63 次、最長 14 站）；之後拿報告的數字對門檻時，以測試的定義為準。審查 L17-22。）全部 **VERIFIED（Linux，本機）**。

## 重現（紅）

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=tymc-old DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_FAST=1 DEPOT_RETURN_STRICT=1 \
  .build/debug/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLineBoughtBefore
# second day 7 of 333 runs not sent out …
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=tymc DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 \
  .build/debug/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testTheTaoyuanAirportLine
# … 63 empty runs between stations to make way (most in a row 14: 桃園機場捷運列車 3, day 0 20:42 to 21:36, 台北車站>三重站>…>泰山站) …
```

第二條的那一段是這次加的（健檢 6.5 (b)），數字和 HEALTH-124 用空車清單數的一樣（63 次、14 站）。

## 證實的原因

1. **舊線不動 2 → 7 是決策 666 的讓路造成的。** 同一個建置把讓路關掉（探針開關），舊線不動是 2/333（長庚醫院 05:56、05:58），和 HEALTH-124 在 `f18c864` 量到的一樣。
2. **傍晚少的班：讓路把那一站唯一在等、幾分鐘後就要發班的車趕走了。** 探針在每次讓路時印出那一站還有幾列在等、下一班從那一站發的 run 還有幾分鐘。舊線不動第 2 天傍晚：

   | 時刻 | 列車 | 從→到 | 那一站在等的車 | 下一班 | 30 分鐘內的班 |
   | --- | --- | --- | --: | --- | --: |
   | 15:44 | 17 | 機場第二航廈→機場旅館 | 1 | 已過 4 分 | 3 |
   | 15:59 | 20 | 機場第二航廈→機場旅館 | 1 | 已過 19 分 | 4 |
   | 16:21 | 28 | 機場第二航廈→機場旅館 | 1 | 4 分後 | 2 |
   | 17:27 | 11 | 台北車站→三重 | 1 | 11 分後 | 3 |
   | 17:36 | 23 | 機場第二航廈→機場旅館 | 1 | 4 分後 | 2 |

   兩天 86 次讓路裡，46 次是那一站只有它、30 分鐘內也沒有班要從那裡發（讓了不礙事）；礙事的是上面這種。讓路挑車時不看它的下一班多近：決策 666 之前它沒有出口，就留在原地接了那一班；現在它被讓到隔壁站，那一班只能等機廠出車，出車的路又常拿不到（[TYMC_AFTERNOON](TYMC_AFTERNOON_2026-11-08.md)）。
   對照：加上「30 分鐘內從這一站發的班不少於這一站在等的車，就不讓」，舊線不動 7 → 3 班（再加偏向機廠是 1 班），改建後 9 → 3 班，讓路 86 → 19–22 次。
3. **決策 666 修好機捷下午，靠的就是同一批讓路。** 機捷（新局）加上第 2 點的條件後，下午的環北↔機場第一航廈又沒發（15:44、16:14、16:19、16:44…，沒發 24/333）。main 的紀錄裡，第 2 天 12:29 列車 17、15:44 列車 18 從機場第二航廈讓到機場旅館，那裡最近的機廠是青埔，12:33、15:48 就進了青埔；下午的區間車要青埔有車才發得出來（TYMC_AFTERNOON 的根因）。所以決策 666 沒有直接修那個根因，是讓路順便把車送進了青埔。**兩個門檻（機捷 ≤ 5、舊線不動 ≤ 2）要的是相反的事**：一個要把機場第二航廈的車趕走，一個要留著。
4. **連讓是「往機廠走到一半折回」。** 列車 3 第 1 天 20:41 從台北車站讓到三重、新北產業園區、新莊副都心、泰山、泰山貴和（都往蘆竹機廠的方向，每一站後面的列車 1 又追上來），到泰山貴和時「最近的月台」是回頭的泰山，就折回一路讓到三重，再折回（6→5→4→3→2→3→4→5→4→5，站號）。每一次都是到站後 3–4 分鐘：讓到的月台就在正線上。改成「挑離機廠最近的、比現在近的月台，沒有才挑最近的」，機捷讓路 64 → 48 次、最長連讓 14 → 4 站、死結 7 列 → 0、空車 667 → 572 km、沒發仍是 5/333，改建後 9/333 不變。
5. **但第 4 點的寫法在舊線不動的世界整條線卡死。** 第 1 天 18:20 起從機場第一航廈、機場第二航廈、坑口卡起，最後全線 32 列，第二天 333 班都沒發，沒有清掉。起頭卡住的是營業車和有班要發的車（列車 1、6、9、11、19、21、22、29），17:55 之後沒有一次讓路參與。這是舊軌道（沒有決策 652 的折返渡線）在兩航廈本來就有的結，main 上只是沒走到。
6. **這三個世界對小改動非常敏感，只調數字等於碰運氣。** 只加「到站後 N 分鐘內不再讓」：舊線不動 N＝1、2、3 分鐘是沒發 1、1、6 班；同樣的 N＝1、2 在機捷是 7、7 班，改建後一個跑不完（卡住）、一個 8 班。

## 每種寫法的數字

沒發／讓路次數／最長連讓／最多死結列數／空車 km。「—」沒跑；「卡」是 20–25 分鐘沒跑完（卡住，逾時）。門檻：機捷 ≤ 5、舊線不動 ≤ 2、改建後 ≤ 9。

| 寫法 | 機捷 | 舊線不動 | 改建後 |
| --- | --- | --- | --- |
| main（決策 666） | 5／64／14／7／667 | **7**／86／9／0／868 | 9／90／11／0／733（讓路與連讓是 HEALTH-124 逐分量的） |
| 關掉讓路 | 12（HEALTH-124，`f18c864`） | 2／0／—／3／581 | — |
| A 往機廠最近的一站，沒有才最近 | 7／70／6／0／640 | 卡（第 1 天 06 時就 20 列死結） | — |
| A，沒有就不讓 | 7／56／7／9／532 | — | — |
| **B 往機廠最遠能到的月台，沒有才最近** | **5／48／4／0／572** | **333／—／—／32／—** | 9／76／10／0／538 |
| B，沒有就不讓 | 13／25／4／0／458 | — | — |
| 到站後 1 分鐘內不再讓 | 7／69／7／7／684 | 1／101／10／0／781 | 卡 |
| 到站後 2 分鐘 | 7／62／9／7／638 | 1／81／7／0／987 | 8／96／7／6／630 |
| 到站後 3 分鐘 | — | 6／71／6／0／922 | — |
| B＋到站後 1 分鐘 | — | 4／108／9／0／948 | — |
| B＋到站後 3 分鐘 | — | 7／73／8／3／988 | — |
| K30：30 分鐘內這一站的班還要它就不讓 | 8／15／4／6／435 | 3／19／3／0／531 | 22／20／3／0／338 |
| K60（60 分鐘） | — | 7／16／3／0／665 | — |
| K10（10 分鐘） | 卡 | 4／37／7／0／537 | — |
| **K30＋B** | **24**／13／1／0／308 | **1**／22／3／7／661 | **3**／24／3／11／521 |
| K10＋B | 10／27／2／0／446 | 1／46／9／0／564 | — |
| K30＋另一座機廠空著就去那座（TYMC_AFTERNOON 的 C） | 8／40／10／0／541 | — | — |
| K30＋B＋C | 10／22／3／0／551 | 6／29／3／15／896 | 5／24／3／4／402 |

三個世界的沒發加起來：main 21；K30＋B 28（機捷 24）；K30＋B＋C 21。沒有一列三格都過。

## 假說與結果

1. 讓到的月台又擋到下一列（決策 666 寫的）→ **對一半**：連讓的每一跳都是後面同方向的車追上來；折回才是多出來的（第 4 點）。
2. 讓路離機廠越來越遠 → **證實**（折回那一半），偏向機廠就少 10 跳。
3. 傍晚少的班是線上空車太多（HEALTH-124 猜的）→ **推翻**：K30 讓空車從 868 降到 531 km 是結果不是原因；少的班是那一站沒車（第 2 點）。
4. 讓路趕走了馬上要發班的車 → **證實**（第 2 點）。
5. 加冷卻就好 → **推翻**（第 6 點：1、2、3 分鐘是 1、1、6 班）。

## 建議的下一步

依序，前一項沒做後一項過不了門檻：

1. **不靠讓路把車送進青埔。** 下午環北↔機場第一航廈要青埔有車（例如傍晚區間車最後幾班收進青埔，或收班後平衡兩座機廠；「另一座機廠空著就去那座」單獨加不夠，見表裡的 C）。做到之後 K30＋B 在機捷才不會掉回 24 班。門檻測試 `TYMC_AFTERNOON=1 AirportShuttleDepotTests` 現在的綠是第 3 點那個副作用撐著的。
2. **舊軌道兩航廈的結要清得掉。** B 在舊線不動觸發的 32 列（第 5 點）不是 B 造成的，但採用 B 之前要先有出口。重現：套下面的實驗 patch，`DEBUG681=3` 跑 `tymc-old`，第 1 天 18:20 起；`DEPOT_RETURN_STUCK_MIN=4 DEPOT_RETURN_STUCK_ALL=1` 會印出每一列在哪、要去哪。
3. 以上兩件之後採用 **K30＋B**：現在它在舊線不動 1 班、改建後 3 班、最長連讓 3 站、讓路 22–24 次。
4. 健檢第 3 項（早上長庚醫院 05:58、體育大學 06:00、長庚醫院 06:07）：每一種寫法、三個世界都還在，和讓路無關（關掉讓路也有 05:58）。沒有查原因。
5. 健檢第 4 項（文湖）：沒有看。

## 健檢 6.5 (a)：門檻測試要不要進每晚 run

**建議不進 `ci.yml` 的每晚 run，改成健檢固定跑的清單**（和 `tymc-old`、`tymc-rebuilt` 的 STRICT 一起）。理由：它在 Linux debug 要 15 分鐘（release 9 分鐘），而第 6 點說這幾個世界的結果會被不相干的小改動翻面，放進每晚 run 會變成一個常紅、紅了又說不出是哪個 PR 的檢查；它現在的綠也不是它想量的那件事撐著的（第 3 點）。等下一步第 1 項做完、結果穩了再放。CI 沒有改。

## 參考庫與外部查找

- 參考庫 `a91453/railway-reference-private`（HEAD d8943125）：**沒有可移植的**。`Simulator/reference_snapshot` 是模型鐵道的配線規劃，列車照道岔路徑走，沒有佔用、機廠、讓車。`Railway/taiwan-rail-reference-clean/source` 執行時照時刻表內插位置（README 寫明列車不會在執行時讓車）；佔用只在離線工具裡（`rail-3d/physical/reservations.js` 的 `vehicleReservations`、`scripts/lib/physical_candidate_conflicts.mjs` 的 `candidateConflicts`、`scripts/optimize_physical_dispatch.py` 的 CP-SAT 模型）。`site_archive_clean` 是它較舊的一份；`world-rail-reference-clean` 位置來自 GTFS；`railway_game_reference_clean` 只有 OpenTTD 編好的 wasm 與設定名，沒有原始碼；`train_loop_reference_clean` 是單列車的環線。借了兩個想法，沒有搬程式：換位置之前先看新位置會不會擋到別人（`candidateConflicts`）；懲罰和上一輪不同的答案來避免來回換（`optimize_physical_dispatch.py` 的 `changes`），這次的「到站後 N 分鐘內不再讓」就是它，結果見第 6 點。
- 外部：OpenTTD（GPL-2.0，只取想法，沒有讀也沒有搬程式）的路徑號誌「只放行到下一個安全等待點」與進機廠的懲罰值的概念，對應 B。沒有用到別的專案。
- 這次的程式（只有測試檔那一段）是本專案自己寫的。

## 附：實驗用的 patch（沒有進 main）

對 main a714b812 的 `Sources/GameCore`。`GameWorld.debug681`：個位 1–4 是 A／A 不退／B／B 不退，9 關掉讓路；十位是到站後幾個 10 分鐘不再讓（表裡的 1、2、3 分鐘是較早一版，乘的是 1 分鐘）；百位是 K 的幾個 10 分鐘；千位 1 是 C。測試那邊在 `wanted()` 開頭加一行 `GameWorld.debug681 = Int(ProcessInfo.processInfo.environment["DEBUG681"] ?? "") ?? 0`。

```diff
diff --git a/Sources/GameCore/Railway/Deadlock.swift b/Sources/GameCore/Railway/Deadlock.swift
index 6ab5552..48802b6 100644
--- a/Sources/GameCore/Railway/Deadlock.swift
+++ b/Sources/GameCore/Railway/Deadlock.swift
@@ -417,18 +417,37 @@ extension GameWorld {
     /// sends it into a depot, or out on a run, as from any station. Its
     /// way into the depot may be long and never free at once on a busy
     /// line, and nothing else moves it.
+    nonisolated(unsafe) public static var debug681 = 0 // [DEBUG-681]
     func depotBoundMakingWay(memo: inout DispatchMemo) -> (train: Train, to: StationID, distance: Int64)? {
         guard isTrafficControlEnabled, !blockSections, trains.contains(where: { $0.execution == nil }) else { return nil }
+        if Self.debug681 == 9 { return nil } // [DEBUG-681]
         let targets: [(station: StationID, berth: Berth?)] = stations.map { ($0.id, nil) }
         var waiting: [TrainID: (candidate: Train, departs: Bool)]?
         for line in lines where line.hasRuns && !line.depots.isEmpty {
             for index in runDepotEntryCandidates(of: line, memo: &memo) {
-                guard let leaving = runDepotEntry(of: line, index: index, memo: &memo)?.leaving,
-                      case .held = reservingDeparture(leaving, memo: &memo.directions)
+                guard let entry = runDepotEntry(of: line, index: index, memo: &memo), let leaving = entry.leaving,
+                      case .held(let holder) = reservingDeparture(leaving, memo: &memo.directions)
                 else { continue }
                 if waiting == nil { waiting = routeWaiting(memo: &memo.directions) }
                 guard !waiting!.isEmpty else { return nil }
-                if let aside = standingAside(trains[index], at: targets, in: waiting!, memo: &memo.directions) { return aside }
+                // [DEBUG-681] keep
+                var keepNote = ""
+                if let st = stationsStoppedAt(by: trains[index].id).first {
+                    let starts = pendingRunStarts(of: line, from: st)
+                    let here = runTrainsWaiting(of: line, at: st).count
+                    let keep = Int64(Self.debug681 / 100 % 10) * 600
+                    keepNote = "nextRun +\(starts.min().map { ($0 - clock.now.seconds) / 60 } ?? -1) here \(here) in30 \(starts.count { $0 <= clock.now.seconds + 1_800 }) in60 \(starts.count { $0 <= clock.now.seconds + 3_600 })"
+                    if keep > 0, here <= starts.count(where: { $0 <= clock.now.seconds + keep }) { continue }
+                }
+                if let aside = standingAside(trains[index], at: targets, in: waiting!, towards: entry.trip.deadhead?.to, memo: &memo.directions) {
+                    print("[DEBUG-681] keep t=\(clock.now.seconds) train \(trains[index].id.rawValue) \(keepNote)")
+                    // [DEBUG-681]
+                    let own = held(trains[index])
+                    let fouled = waiting!.keys.sorted().filter { $0 != trains[index].id && network.fouls(own, routeEnvelope(of: waiting![$0]!.candidate).resources) }
+                    let here = stationsStoppedAt(by: trains[index].id).map { "\($0.rawValue)" }.joined(separator: "/")
+                    print("[DEBUG-681] yield t=\(clock.now.seconds) d\(clock.now.seconds / 86_400) \(clock.now.seconds % 86_400 / 3_600):\(clock.now.seconds % 3_600 / 60) train \(trains[index].id.rawValue) at \(here) to \(aside.to.rawValue) dist \(aside.distance) depot \(entry.trip.deadhead.map { "\($0.to.rawValue)" } ?? "-") depotHeldBy \(holder.rawValue) fouls \(fouled.map(\.rawValue)) lastTT \(trains[index].timetable.last.map { "\($0.station.rawValue)@\($0.arrival.seconds)" } ?? "-")")
+                    return aside
+                }
             }
         }
         return nil
@@ -451,8 +470,20 @@ extension GameWorld {
     /// ``spareStandingAside(in:memo:)``), with the station and the way's
     /// length, or `nil`.
     private func standingAside(_ spare: Train, at targets: [(station: StationID, berth: Berth?)],
-                               in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DirectionMemo) -> (train: Train, to: StationID, distance: Int64)? {
+                               in stuck: [TrainID: (candidate: Train, departs: Bool)], towards depot: StationID? = nil, memo: inout DirectionMemo) -> (train: Train, to: StationID, distance: Int64)? {
         guard let place = spare.placement else { return nil }
+        // [DEBUG-681] variants
+        let variant = depot == nil ? 0 : Self.debug681 % 10
+        let cooldown = depot == nil ? 0 : Int64(Self.debug681 / 10 % 10) * 600
+        if cooldown > 0, let last = spare.timetable.last, spare.timetable.count == 2, stationsStoppedAt(by: spare.id).contains(last.station),
+           clock.now.seconds - last.arrival.seconds < cooldown, station(id: spare.timetable[0].station)?.isDepot == false { return nil }
+        func left(_ p: TrainPlacement) -> Int64 {
+            guard let depot else { return .max }
+            return [p, turnedRound(p)].compactMap { path(from: $0.position, toStation: depot, length: spare.length)?.distance }.min() ?? .max
+        }
+        let leftHere = variant == 0 ? Int64.max : left(place)
+        var bestKey = Int64.max
+        var fallback: (train: Train, to: StationID, distance: Int64)?
         let own = held(spare)
         let waiting = stuck.keys.sorted().filter { $0 != spare.id && network.fouls(own, routeEnvelope(of: stuck[$0]!.candidate).resources) }
         guard !waiting.isEmpty else { return nil }
@@ -462,7 +493,7 @@ extension GameWorld {
         for start in starts {
             for target in targets {
                 guard let way = path(from: start.position, toStation: target.station, length: spare.length, avoiding: blocked, only: target.berth),
-                      way.distance > 0, way.distance < best?.distance ?? .max
+                      way.distance > 0, variant != 0 || way.distance < best?.distance ?? .max
                 else { continue }
                 var moving = spare
                 moving.position = start.position
@@ -488,9 +519,15 @@ extension GameWorld {
                     return false
                 }
                 guard frees else { continue }
-                best = (granted, target.station, way.distance)
+                if variant == 0 { best = (granted, target.station, way.distance); continue }
+                if way.distance < fallback?.distance ?? .max { fallback = (granted, target.station, way.distance) }
+                let leftThere = left(there)
+                guard leftThere < leftHere else { continue }
+                let key = variant <= 2 ? way.distance : leftThere
+                if key < bestKey { bestKey = key; best = (granted, target.station, way.distance) }
             }
         }
+        if variant == 1 || variant == 3 { return best ?? fallback }
         return best
     }
 
diff --git a/Sources/GameCore/Railway/RunDepot.swift b/Sources/GameCore/Railway/RunDepot.swift
index d05b6c0..2a67159 100644
--- a/Sources/GameCore/Railway/RunDepot.swift
+++ b/Sources/GameCore/Railway/RunDepot.swift
@@ -61,7 +61,7 @@ extension GameWorld {
     /// facing the other way that its runs from there do not need (one
     /// each, in ID order), which take a run this way turned round rather
     /// than leave it to a train out of the depot, or go in when none does.
-    private func runTrainsWaiting(of line: ServiceLine, at station: StationID, way: RingDirection? = nil) -> [Int] {
+    func runTrainsWaiting(of line: ServiceLine, at station: StationID, way: RingDirection? = nil) -> [Int] {
         let waiting = line.trains.compactMap { id -> Int? in
             guard let index = trains.firstIndex(where: { $0.id == id }) else { return nil }
             let train = trains[index]
@@ -175,6 +175,11 @@ extension GameWorld {
             guard let other = otherDepotRun(of: line, for: trains[index], besides: depot, memo: &memo.directions) else { return nil }
             trip = other
         }
+        // [DEBUG-681] C: to a depot standing empty
+        if Self.debug681 / 1000 == 1, isTrafficControlEnabled, !blockSections, let depot = trip.deadhead?.to {
+            let empty = line.depots.filter { d in d != depot && depotHasRoom(d, for: trains[index]) && !trains.contains { $0.execution == nil && isStopped($0, at: d) } }
+            if !empty.isEmpty, trains.contains(where: { $0.execution == nil && isStopped($0, at: depot) }), let other = emptyRun(of: line, for: trains[index], to: empty) { trip = other }
+        }
         return (trip, firstDeparture(of: trains[index], on: trip, calling: line.stops))
     }
 
```
