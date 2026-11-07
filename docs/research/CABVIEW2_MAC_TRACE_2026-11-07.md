# CABVIEW-2：高雄環狀輕軌 3D 跟車 10× 的實機 Instruments 量測（2026-11-07）

作者的 Mac（M6）上的 Claude Code session（CABVIEW-2-MAC），分支 `claude/cabview-2-mac`，從 `main` `a3c83a0b9` 開。結論與修法寫進決策 379 續三（[docs/decisions/379.md](../decisions/379.md)）。

## 問題

作者回報（119.1）：實機 3D 地圖跟車（車窗視角），高雄環狀輕軌，10×，列車「動 0.3 秒、停 2.2 秒」，約每 2.5 秒一次。

## 怎麼錄的

- 裝置：iPhone 17 Pro（iOS 27.3），透過 Wi-Fi 連 Mac（CoreDevice `localNetwork`）。Xcode 27.2（27B52）。
- 建置：Release（`xcodebuild -configuration Release`，裝置簽章用 `DEVELOPMENT_TEAM` 從命令列給，沒有寫進任何檔案；`docs/MAC_LOCAL_SETUP.md` §4.2、§7），`xcrun devicectl device install app` 裝到手機。
- 錄法：`xcrun xctrace record --template "Time Profiler" --instrument "Hangs" --instrument "Hitches" --device <iPhone> --time-limit 240s --window 30s --launch -- io.github.a91453.RailwayGame`。Instruments 從 Mac 開 App，作者在 3 分鐘內進到高雄環狀輕軌的 3D 跟車、開 10×，放著不碰；只留最後一段（存下的檔案實際保留了 60 秒）。
- 兩次：改前（10:25，`main` 的程式）與改後（10:43，這個分支的修法）。`.trace` 各 14 MB，沒有提交；摘要用 `xctrace export` 匯出 `time-profile`、`potential-hangs`、`hitches` 表，再用 Python 整理（主執行緒每 100 ms 的忙碌、各函式的 inclusive 時間、每個 tick 的開始與長度）。
- 遇到的狀況：
  - 第一次 `xctrace` 說 "Timed out waiting for device to boot"，`xctrace list devices` 把手機列在 Offline；跑一次 `xcrun devicectl device info ddiServices --device <iPhone>` 之後就變成 online。
  - `--attach` 找不到 App 時（App 沒在前景），改用 `--launch`。
  - Hitches 的表（`hitches`、`hitches-frame-lifetimes` 等）全是 0 列：這個 App 用 Metal 自己畫，Wi-Fi 連線下沒收到資料。所以每幀時間改由 Time Profiler 推：主執行緒連續落在 `Map3DMetalView.draw` 裡的取樣算一幀。

## 改前的數字（60 秒）

**主執行緒沒有卡住**：

| | 數字 |
| --- | --- |
| Hangs | 0 |
| 主執行緒 CPU | 11.85 秒／60 秒；每秒中位數 199 ms、最多 315 ms；任何 100 ms 裡最多 91 ms |
| 每幀（`Map3DMetalView.draw`） | 中位數 2 ms、p90 3 ms、p99 6 ms、最長 14 ms |
| 幀與幀的間隔 | 中位數 17 ms、p90 21 ms、p99 30 ms、最長 57 ms（約 60 fps） |
| 主執行緒上的 `trainMotion(after:at:)` | 只有 2 次取樣（`glideMemo` 有用到，滑行在背景算） |

**背景的 tick**（`GameSession.LoopTick.work()`）：

| | 數字 |
| --- | --- |
| 一輪（遊戲迴圈的一步）的間隔 | 40 輪，中位數 1.53 秒（1.17–1.91 秒） |
| 一輪幾個 tick | 平均 4.4 個（上限 5，`maximumStepDuration` 500 ms） |
| 一輪最後一個 tick 的 `TrafficReading` | 752–1,220 ms，平均約 1,000 ms |
| 一輪的 `GameWorld.advance` 合計 | 59–424 ms |
| 背景 CPU | 約 60 秒／60 秒（約一顆核心一直在忙） |

逐毫秒看一輪（41.39 秒開始的那一輪）：

```
41.390–41.414  tick 1、2 的 advance 與滑行（各 3–4 ms）
41.438–41.475  tick 3、4（各 1 ms 以內）
41.476–42.239  tick 5：TrafficReading 763 ms
42.243         tick 5 交給主執行緒
42.813         下一輪開始（TickPace 休息約 570 ms）
```

**停住的時候（40 次交通讀數的時間窗，共 40.0 秒）主執行緒最重的 10 個**（inclusive，App 自己的函式，括號是每個時間窗平均）：

| # | ms | 函式 |
| --: | --: | --- |
| 1 | 4,054（101） | `@objc Map3DMetalView.draw(_:)` |
| 2 | 3,922（98） | `Map3DMetalView.draw(_:)` |
| 3 | 2,784（70） | `closure #2 in Map3DView.showTrains(in:on:context:)` |
| 4 | 2,045（51） | `static Map3DTrains.frame(_:progress:heights:in:models:eye:palette:ringed:reach:)` |
| 5 | 2,019（50） | （同上，specialized） |
| 6 | 841（21） | `Map3DTrains.cars(of:progress:heights:models:)` |
| 7 | 736（18） | `Map3DModelPack.index(of:)` |
| 8 | 729（18） | `Map3DRealTrains.add(to:second:day:dayBefore:models:eye:reach:)` |
| 9 | 665（17） | `Map3DModelPack.models(forType:)` |
| 10 | 664（17） | `Map3DModelPack.drawn(_:)` |

主執行緒在這些時間窗裡每 1 秒只忙 124 ms，全部在畫 3D。**同一段時間背景最重的 10 個**：

| # | ms | 函式 |
| --: | --: | --- |
| 1 | 39,670（992） | `TrafficReading.init(world:train:in:previous:)` |
| 2–3 | 39,670（992） | `GameSession.LoopTick.work()` 的 closure |
| 4 | 39,655（991） | `GameWorld.routeWaits()` |
| 5 | 39,645（991） | `GameWorld.deadlock(memo:)` |
| 6 | 38,783（970） | `GameWorld.departureRequest(of:memo:)` |
| 7 | 38,775（969） | `GameWorld.trafficPlan(memo:)` |
| 8 | 38,772（969） | `GameWorld.trafficPlan(parts:)` |
| 9 | 38,649（966） | `GameWorld.trafficPoints(of:cycle:)` |
| 10 | 38,226（956） | `GameWorld.preferredPath(from:preference:length:memo:)` |

背景整段最常停在的地方（self）：`__RawDictionaryStorage.find` 7.1 s、`TrainRoute.shortest` 6.7 s、`Set.insert` 3.3 s。

## 根因

不是主執行緒的工作：主執行緒每幀 2 ms、0 個 Hang，畫面一直約 60 fps。景物停住是**滑行停了**：

1. 遊戲迴圈一步最多 5 個 tick，一個接一個算（決策 143），算完一個就換上世界。只有最後一個 tick 讀交通控制（`readsTraffic = index == ticks - 1`）。
2. 在這條線上，前 4 個 tick 各只要 1–80 ms，約 0.1 秒內全部換上；最後一個 tick 的 `TrafficReading`（`routeWaits()` 的死結搜尋 → `trafficPlan` → `preferredPath`／`TrainRoute.shortest`）要 0.75–1.2 秒（作者 119.1 那次約 2.2 秒）。
3. 每個 tick 的滑行長度＝它和上一個 tick 的間隔（決策 379 續，`TrainMotion.glideSeconds`）。所以前 4 個 tick 的路程在約 0.1–0.3 秒內滑完（「動 0.3 秒」），接著到最後一個 tick 換上之前都沒有新的滑行，車頭與跟著它的鏡頭整個停住，停的時間就是交通讀數的時間（「停 2.2 秒」）。

雲端懷疑的三項：`routeWaits()` 的死結搜尋就是讓最後一個 tick 慢的原因，但它在背景；`glideMemo` 有用到，主執行緒沒有重算滑行；`TrainMotion.glideSeconds` 本身是對的，但一步裡 tick 擠在一起時，各滑各的就會走走停停。

## 修法（決策 379 續三，只動 GamePresentation 與 App，GameCore 不動）

- 一步裡不是最後的 tick（`LoopTick.stepGoesOn`），照舊算完就換上世界（指令最多等一個 tick 就生效，決策 143 不變），但不算自己的滑行；`GameSession.glidesOnThroughTheStep` 在那個世界版本上為真。
- 這時 `trainMotion(after:at:)` 回傳正在顯示的滑行，讓它繼續滑；一步的最後一個 tick 在背景從這一步開始前的滑行算到最後的世界（`glideToGoOnFrom` 就是那個顯示中的滑行），長度＝兩步之間的間隔。
- 真實列車與公車的時鐘（3D 的 `updateRealClock`／`updateBuses`，2D 的 `realTrainClock`）在同樣的 tick 不重算，一起滑過整步。
- 只在 10× 與 60×：600× 以上一步的軌道可能經過好幾站，超過滑行能跟的距離（40 km 的 `longestGlide`），照舊每個 tick 各自滑。3D 跟車最多 10×（決策 360）。
- 有指令（暫停、改速度、建造）就換世界版本，`glidesOnThroughTheStep` 變成假，地圖照舊自己算。

## 改後的數字（60 秒）

| | 改前 | 改後 |
| --- | --- | --- |
| Hangs | 0 | 0 |
| 主執行緒 CPU／60 秒 | 11.85 秒 | 10.81 秒 |
| 主執行緒每秒（中位數／最多） | 199／315 ms | 168／297 ms |
| 每幀 draw（中位數／p99／最長） | 2／6／14 ms | 1／7／14 ms |
| 幀間隔（中位數／p99／最長） | 17／30／57 ms | 17／29／61 ms |
| 主執行緒上的 `trainMotion(after:at:)` | 2 次取樣 | 0 |
| 一步的間隔（中位數） | 1.53 秒 | 1.42 秒 |
| 最後一個 tick 的 `TrafficReading` | 752–1,220 ms | 711–800 ms |

tick 的節奏改前改後差不多（修法沒有動 tick），差別在滑行。Instruments 量不到畫面上的車停了多久，所以用兩次錄製裡真實的 tick 完成時間（背景的 advance／`TrafficReading` 取樣結束的時間），照兩種規則算 30 fps 下車頭停住的格數：

| tick 的時間取自 | 舊規則（每個 tick 各滑） | 新規則（一步滑一段） |
| --- | --: | --: |
| 改前那次 | 62 % 的格停住 | 11 % |
| 改後那次 | 37 % | 3 % |

剩下的 3–11 %：一步的間隔每次不同，這一步比上一步久時，上一段滑完到下一段開始之間會停一下。作者用眼睛看改後的版本：「有順很多了」。

Mac 上的測試（`swift test`）：`TrainMotionTests.testAFollowedTrainMovesEveryFrameThroughAStepOfTicksBackToBack` 照實機的節奏（前 4 個 tick 隔 20 ms、最後一個 0.8 秒後、休息 0.6 秒）：舊規則 6 步裡停住超過 60 格，新規則 0 格；`testACommandWithinAStepEndsItsGlide`。GamePresentation 裡和滑行、跟車、交通、遊戲迴圈、3D 有關的 1,817 個測試（76 個跳過）都過，只有 `Map3DModelPackLockTests` 兩個、`Map3DFarSets422Tests.testTheNearCarsAreUnchanged` 一個紅：沒有這個修法的 `main` 在這台 Mac 上也一樣紅（模型頂點的雜湊在 macOS 與 Linux 不同），不是這次的事。

## 還沒做的

- **代價**：畫面上的車比世界晚一步（這條線約 1.4 秒），到站聲會比畫面上的車早到（決策 379 續已經接受晚一個 tick 的間隔，這次多了一步裡其他的 tick）。
- **交通讀數本身**：每一步仍要 0.7–1.2 秒，遊戲在這條線上的 10× 實際只跑到約三成（一步 4.4 個 tick／1.5 秒 ≈ 每秒 2.9 個 tick，應有 10 個），背景一直佔一顆核心。3D 跟車時沒人看交通圖，可以少讀（HANDOFF §4.54 ①），但讀數會被列車面板的等候文字與單線待避提示讀到，改之前要先讓過期時的背景讀（`readTrafficOffTheMainActor`）一次只跑一個。
- **作者回報：第一次跟車沒多久就跳回 2D**。程式裡會自動關 3D 的只有放空模式（從選單才會開）、3D 的「2D」「建設」按鈕、捏合交回（跟車時不會）；這次的修法沒有動這些。還不知道原因，要作者再遇到時記下：怎麼開始跟的（2D 跟車列的 3D 按鈕、或 3D 裡點車）、有沒有轉手機、跳回之前有沒有跳出卡片或報表。
- 真實列車的時鐘只在 App 這邊用 `glidesOnThroughTheStep` 擋，GamePresentation 的 `RealTrainClock` 本身沒有改。
