# 交接：PR #1019–#1030 發版前小審查（審查 E）

Session：發版前小審查。派工：遊戲規劃 session_01CHQg7B6JqzbScGSjyDwHos（10-22 換手後是 session_01Ddr2wiXx1Xhn2m9qNBDnDh），日期 2026-10-22。派工單：TestFlight 第 82 版之前，看審查 D（#1018）之後合併的程式 PR；不足 30 點也做，因為要發版（HANDOFF §2.0「發版前」）。

- 審查基準：`main` **e6e8f5a9**（#1029 合併後）。#1029 先看了 head 48ee577e，合併時的 head 是 **4333a75c**，多出來的那個 commit 也看了。
- 範圍：#1019–#1030。點數照 HANDOFF 第 1 節「多久審查一次」計算。
- 上一輪：[PR962_1018](PR962_1018_REVIEW_HANDOFF.md)（審查 D）。
- 存檔版本、決策編號、golden schema 都**不動**。GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）。不代表 iOS、Metal 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 範圍內的 PR | 12 個：#1019–#1030 |
| 程式 PR（有點數） | **8 個、9 點**：GameCore 1 個（#1019）2 點；#1020、#1021、#1023、#1025、#1026、#1029、#1030 各 1 點 |
| 0 點（跳過） | 文件 4 個：#1022、#1024、#1027、#1028 |
| P1、P2 | **0 個** |
| P3 | **2 個**（E1、E2，第三節），都只在測試版的演示模式，沒修 |

**可以發**（main e6e8f5a9）。發版前仍要照 HANDOFF §2.0：那個 commit 在 main 上的 `ci.yml` 與 full lane 都綠。

特別看的三件事：

- **舊存檔與 replay**：沒有 PR 改存檔格式。#1019 只改 `DirectionMemo`（每次推進才算、不存進存檔）與方向保護的豁免。`long-leg-traffic.json` 的重錄見第二節，逐值說明是合理的。
- **Release 版當掉**：沒有新的 `preconditionFailure`、`fatalError`、強制解包或沒有保護的索引。#1029 的 `built[index]` 只用 `platformStretches` 裡小於 `buildable` 的前段（`reached` 的 `prefix`），迴圈每次至少前進 1 站，一定會結束。
- **演示模式在 App Store 版**：完全看不到。設定的開關（`if TestBuild.isTest, …`）、`RootView` 設給 `launcher.isDemoMode` 的值、#1029 的鈕，三處都經過 `DemoMode.isOn(testBuild: TestBuild.isTest, …)` 或 `TestBuild.isTest`。App Store 版的收據不是 `sandboxReceipt`，所以就算裝置裡留著 `demoMode.on = true` 也打不開。只有審查員的機器例外，見 E1。

## 二、逐 PR

| PR | 點 | 看了什麼 | 結論 |
| --- | --: | --- | --- |
| [#1019](https://github.com/a91453/railway-game-ios/pull/1019) | 2 | 決策 344：線的計畫把第一段分開算，只有某一股出發才走的行經（`departures`）。往那一站的路逆著這些行經走時，如果別的列車與計畫都沒有反方向走同一段，就不算違反方向保護（`firstCallTraversals`）。正在跑的列車的 `serviceDirections` 一律不算豁免，所以停在那一股、要從那裡出發的列車還是擋得住。`Set` 的走訪順序不影響結果（只問是否包含），保持決定性 | 無問題 |
| 同上，replay | | `long-leg-traffic.json`：checksum 0、1 不變（死結前的狀態相同），2–5 換了。舊程式第 35、40 個指令時有 2 列、4 列死結；新程式往 A 的列車進 A 的待避線，沒有死結。和改的程式對得上：A 是兩條環狀線的第一站，正好是這次放寬的情況。`ReservationShortcutTests` 改成每分取一個狀態，原因是跟車的狀態變少，檢查本身沒有放寬 | 合理 |
| [#1021](https://github.com/a91453/railway-game-ios/pull/1021) | 1 | 3D 地圖放同一個 `SpeedControl`，`tutorialTarget` 傳 `nil` | 無問題 |
| [#1023](https://github.com/a91453/railway-game-ios/pull/1023) | 1 | 審查 D 的 D1、D2：公園回傳占用的格子；種子改用地圖座標（`originX / metre + x`）。座標到 `Int` 的轉換在台灣範圍內不會溢位 | 無問題 |
| [#1020](https://github.com/a91453/railway-game-ios/pull/1020) | 1 | 決策 350：`MapCornerButtons.place`。`ContentView` 與 `MapView` 各算一次，前者含資訊卡的寬度。兩邊不一致時最多是鈕在角落多出現一次，不會當 | 無問題 |
| [#1025](https://github.com/a91453/railway-game-ios/pull/1025) | 1 | 決策 349：uniform 的 `fog.zw` 與天空的 `stars.yzw` 原本都是 0、沒人讀。`map3dHaze` 在高處往下看時 `k` 是負的，`end` 夾在 −8，`exp(8)` 不會溢位，分子分母同號；`pow` 的輸入都先夾到 ≥ 0 | 無問題（Metal 只做靜態比對，UNVERIFIED） |
| [#1026](https://github.com/a91453/railway-game-ios/pull/1026) | 1 | 決策 351：`begin` 在 `news == nil` 時才把新局標成演示。讀檔、匯入、自動存檔都帶 `news`（`SaveLibrary.news(for:)` 不是 optional），所以**舊存檔不會被標成演示**。課程在演示模式下也算演示，不記星星（決策寫的就是這樣） | 無問題 |
| [#1029](https://github.com/a91453/railway-game-ios/pull/1029)（4333a75c） | 1 | 決策 351 續篇：每一步都是玩家的指令（GameCore 照常檢查），`canLayDemoRealLines` 要 `news.isDemo`。`plan` 的 `low` 有 `guard low >= 0`，`chains` 的運算有界，`layDemoRun` 的 `reached ≥ 1`。最後一個 commit 照真實的隧道與高架鋪：每段試 3 個高度，取到得了最多站的那個；`built[index]` 仍只用 `buildable` 以內的；`demoKeepsRealStructures` 與 `networkHeight` 在 `defer` 裡還原 | E2（P3） |
| [#1030](https://github.com/a91453/railway-game-ios/pull/1030) | 1 | `Web/CityView` 的「技術試作」標示：`?app=1`（遊戲裡）時移除，中文用固定字串寫進 `innerHTML`，沒有外來輸入 | 無問題 |

## 三、P3（沒修）

- **E1：審查員的機器上也開得出演示模式的開關**（#1026，同樣適用決策 338 的列車包開關）。
  - 原因：`TestBuild.isTest` 在 Release 版看收據是不是 `sandboxReceipt`。App Review 用的機器也是沙盒收據。
  - 重現：送審的版本，在設定的「版本」那一列連點 5 下，開關就會出現。
  - 影響：只有審查員看得到，一般 App Store 使用者看不到。風險是審查準則 2.3.1 的「隱藏功能」。
  - 建議：送審 App Store 之前，Release 版的開關改用編譯旗標（例如只有 TestFlight 的 workflow 才加的 `-D TESTFLIGHT`），不再靠收據判斷。TestFlight 內測不受影響，所以第 82 版不用等這一項。
- **E2：一鍵鋪路線在鋪的途中，玩家還能操作**（#1029）。
  - 原因：`layDemoRealLines` 在一個編輯手勢裡多次 `await Task.yield()`。鋪的時候鐘停著，但暫停與倍速鈕沒有停用（HUD 與 #1021 的 3D 地圖都有），復原鈕也沒有。
  - 重現：鋪的途中按「播放」，tick 會插進同一次復原；按「復原」，會在手勢還沒結束時退回一部分。
  - 結果：一次復原退不完全部。不會當，也不影響存檔。
  - 只在測試版的演示局。建議在 `demoRealLinesProgress != nil` 時停用速度與復原鈕；不急。

## 四、驗證

- **VERIFIED（Linux，Swift 6.4.0，main 8a803e60）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨通過。
  - `swift test --skip-build --filter` 跑了 `ReplayFixtureTests`（含 `long-leg-traffic.json`）、`FirstStopBerthTests`（2 個）、`Map3DParksTests`（8 個），全部通過。
- **UNVERIFIED**：
  - #1020、#1025、#1026、#1029、#1030 在本機只讀程式，沒有建置與測試；它們 PR 的 CI 結果見各自的 Checks。
  - Metal 著色器、實機畫面、演示模式在 TestFlight 版的實際行為。
