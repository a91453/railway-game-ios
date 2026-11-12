# DEMO-KRTC

派工單 DEMO-KRTC（session_01YGNNumAf5JwZBLQzSMsM3H，`claude/demo-krtc`，2026-11-12；遊戲規劃第 63 任派，#1579 留言 6831260703）。不動 GameCore、存檔版本、golden、ReplayFixtures、SaveFixtures；沒有用決策號（710 釋出）。兩件都是 COACH-HEALTH 量測時看到的（`docs/research/COACH_HEALTH_2026-11-12.md`「另外看到的」）。

## 1. 示範「鋪真實路線」只鋪高雄捷運：3 線 74 站 0 車

**重現**：`DemoRealLinesEverySystemTests.testKaohsiungsMetroHasTrains`，在 App 開的示範世界（`GameLauncher.newWorld(demo: true)`，全臺、有地形）只鋪 `krtc`。修之前紅、橘、環狀輕軌三條都沒有車。

**不是 #2094 造成的**：把 `DemoRealLines.swift` 換回 #2094 之前（ba011b2）再跑同一個測試，一樣三條都沒車（VERIFIED，Linux）。從決策 571 起就有。

**原因有兩個，都在 GamePresentation**：

1. `besidePlatformStretch(of:)`（決策 285、571）在月台兩端「往內 1 單位」找旁邊那股。雙線的第二股接點和第一股差 3～4 單位（各自在自己的曲線上取整數），所以整段 edge 的月台，一端往內 1 單位常常找到旁邊「下一段 edge」的第 1 單位，兩端不是同一段 → 判定旁邊沒有可放月台的軌道 → 那一站只有一股有月台。高雄紅、橘線大約一半的站這樣。列車在某股上到了只有另一股有月台的站，沒有路（`linePath` 找不到）→ `lineJourney` 是 nil → `staffLine` 丟 `unknownLine`，`addDemoLine` 用 `try?` 吞掉 → 0 車，訊息還說有車。
   - 改法：往內 `DoubleTrack.besideInset`（0.25 m，最多月台的四分之一）找，再把月台兩端量回那段 edge 上。
2. 一段鋪設的兩端，渡線在最後一個月台「外面」150 m（`DemoRealLines.runOn`），決策 571 的規則「200 m 內有道岔就只給點到的那股月台」讓端點站只有一股有月台。回程走另一股的車到端點站沒有月台可停（渡線在月台外面，要折返才過得去）。環狀輕軌、三鶯線頂埔–三峽是這個。
   - 改法：`besidePlatformStretch(of:joined:)`／`besidePlatform(of:joined:)` 多一個參數，示範鋪線（`addDemoPlatform`）傳 `true`，端點站兩股都有月台；玩家的月台工具照舊（預設 `false`）。

**回歸測試**：`testALineOfEachSystemHasTrains`，十個系統各鋪一條線的前 4 站，每條都有車、車都在軌道上。

## 2. 全島世界收購機場捷運（`tymc:A`）回報坡度太陡

**重現**：世界選在 25.02, 121.30（COACH-HEALTH 用的點）時，示範世界和**玩家的正式世界**（`demo: false`）都拒絕；選在台北、板橋、桃園的世界買得到。所以正式遊戲會遇到，看玩家開局選的點。

**原因不是林口的坡**：`RealLineAcquisition` 沿線每 32 m 讀一次地面，最後一步停在終點前最多 32 m。地面是一塊一塊讀的，塊的邊界跟世界選在哪有關；選在 25.02, 121.30 時，老街溪站後面最後幾十公尺落在沒讀的那一塊，高度當成 0（海平面），而車站在 133 m：110 m 內降不下去，`TrackRise` 無解，報「坡度太陡」。

**改法**：沿線取樣多取路線（與機廠路徑）的終點那一點。`AirportLineWholeIslandTests.testItIsOnSaleInAWorldPickedBesideIt`（玩家世界與示範世界各一次）修前紅、修後綠。

## 還留下的

- **示範鋪線的訊息不誠實**：某條線配不到車時（`staffLine` 丟錯），`layDemoRealLines` 的訊息照舊說列車在跑。這次沒改（原因修掉後十個系統都有車）；要改的話讓 `addDemoLine` 回報有沒有配到車、訊息另寫一句。
- **真愛碼頭**（環狀輕軌）月台被拒（`onWater`），那一站略過，訊息照規矩說「有 1 個車站略過」。沒修。
- 示範的雙線列車各自在一股上來回（端點站在哪股到就在哪股折返），不是靠左行駛的循環；示範鋪線會關行車控制，所以不會死結。要像收購的線那樣跑，得把渡線移到端點月台靠線內的一側，另外派。
- 沿線取樣多一點，理論上會讓某條線的終點多讀一塊地面、在逐格買地的世界多買一格地（終點剛好跨格時）。六個城市開局的價格表（`ACQUIRE_REPORT=1 ACQUIRE_ONLY=cities`）**沒有重跑**，UNVERIFIED。
- 淡水開局的機場捷運照舊不賣（過水太低，決策 556 已記），不是這次的原因，沒動。
- 3D／實機沒有看：請 Mac session 在示範模式只鋪高雄捷運看一眼（三條線都有車、端點站兩股都有月台）。
