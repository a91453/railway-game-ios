# 公測前抓蟲：經營與存檔（2026-10-30）

派工單 BH3（session_01YGNNupmfpuBKeRdCH2HRPJ，由遊戲規劃第 32 任派出），分支 `claude/bughunt-economy-saves`。對照的是 `main` `9fb305d`（#1520 之後）。範圍：資料面板、財務（收入、支出、貸款、破產、稅）、月報與年度決算（含「再開上個月月報」）、子公司與建物收益、城市成長與請求、目標與成就、新遊戲流程、存檔、自動存檔、讀檔、匯出、舊存檔相容、設定、回報問題、測試版開關。

**結論：沒有找到 P1。** 下面 §2 是實際「玩」過、結果正常的部分（之後的人不必重做），§3 是 P2／P3。

## 1. 怎麼玩的

都在 Linux（Swift 6.4.0，雲端容器）用既有的無頭方式：`HeadlessGame`（決策 260，經過 `GameSession`，和裝置同一條路）、`Policy` 的腳本玩法（決策 261）、`SaveLibrary.encode`／`decode`（App 存讀檔用的同一個檔案格式）。臨時測試檔放進 `Tests/GamePresentationTests/` 跑過後刪掉，沒有提交。

「存→讀→繼續」的比法：同一個世界分兩份，一份一直玩，另一份每個午夜存檔、讀回、用讀回的世界繼續玩；每天比兩份世界是否完全相同（`GameWorld` 的 `==`），並比存前與讀回是否相同。

## 2. 玩過、正常的（VERIFIED，Linux）

| 玩了什麼 | 結果 |
| --- | --- |
| `SaveFixtures/` 全部 79 個（v1–v75，含示範地圖、整島、貨運、子公司、觀光、城市請求、無限資金、收購、公車與道路）各自讀進來玩 31 天，每個午夜存→讀→繼續 | 79 個都沒有分歧、讀回都相同、沒有當掉（debug，58 分鐘）。v16 跨過第 1 年決算（第 360 天），v41、v72 跨月 |
| 新竹（`tra-hsinchu`）實景地圖，簡單與寫實規則各一局：`two-towns` 腳本蓋線玩 2 天，再每天存→讀玩 5 天 | 都相同；存檔約 0.78 MB |
| 整個臺灣新局（`newWholeTaiwanGame` 加預設選項）玩 3 天，每天存→讀 | 相同 |
| 臺灣 27 個實景起點（`RealWorldPlace.all` 中有 `RealWorldExpansion` 的）各開一局、讀地、玩一天、存→讀 | 都相同。金門、馬祖與 173 個海外城市走另一條（沒有逐塊買地）的開局，沒有逐一跑 |
| 挑戰「三鎮連線」：借滿 $5,000,000、錢花光買車，讓現金轉負，每天存→讀 | 第一次轉負時新聞寫「現金低於零。破產倒數 59 天。」，倒數每天減一；第 60 個赤字午夜判破產（第 132 天），破產後的存檔照樣讀回、再玩 3 天也讀回；挑戰結束後可以改自由模式 |
| 借款：一步 $100,000 借到上限 50 步，第 51 步被拒（訊息寫上限），利息每天照 5%／360 天扣 | 正常 |
| 既有的測試類別（`SavedGameTests`、`SaveLibraryTests`、`AutosaveSlotsTests`、`GameLauncherTests`、`MonthlyReportTests`、`FareAndLoanPreviewTests`、`CityRequestsSessionTests`、`SubsidiarySessionTests`、`AchievementsTests`、`NewGameChoiceTests`、`SaveRecoveryTests`、`BackgroundSaveTests`、`ProblemReportTests`、`FinanceCompositionTests`、`FinanceHistoryTests`、`SaveNamingTests`、`SaveSyncTests`、`NewGameSavePropertyTests`）在這個 `main` 上 | 全綠 |

讀過程式、沒有發現問題的路徑（靜態檢查，不是執行驗證）：
- 自動存檔輪替（決策 192）、回到之前的自動存檔與復原、從開始畫面回去、新局把舊的自動存檔收成玩家存檔；決策 473 新加的「取消讀取」：讀檔在存檔佇列上做完才看取消，取消時已寫的那份輪替存檔留著，Continue 仍讀得到最新的一份。
- 在遊戲中打開朋友的路網（決策 409）：先自動存檔玩家自己的局；「只看」時不寫任何存檔。
- 玩家偏好檔（`LauncherPreferences`）：`LessonPlay` 的四個欄位同一個提交加的，舊檔不會因缺欄位整份讀不回。
- 無限資金：不能借款、成就與公司評等不算（從世界讀，存讀後也不算）。
- 10/25 之後合進來、碰到這個範圍的改動（#1520 再開月報、決策 480 收支甜甜圈、決策 471 財務趨勢與帳目不再每 tick 重算、決策 473 載入步驟與取消、決策 490 收購當天的線）彼此沒有打架。

## 3. P2、P3

沒有 P2。

### P3-1 月報標題在「轉成赤字」的月份仍說「平穩的一個月」

- **在哪**：`Sources/GamePresentation/MonthlyReportText.swift` 的 `MonthlyReport.make`，標題只看淨利正負變號、票收與運量紀錄、最大變化，不看現金。
- **怎麼重現**：三鎮連線挑戰，開局借滿、錢花在買車（不上線），每月淨利一樣是小虧損；第 3 個月現金轉負、新聞出現破產倒數，月報標題仍是「平穩的一個月，變化不大」。
- **建議修法**：`cash.previous >= 0 && cash.value < 0` 時標題改成「現金轉為赤字」（`MonthlyHeadline` 加一種），排在 `turnedLoss` 之後；挑戰有破產天數時一起寫倒數。GamePresentation 加一個 Linux 測試。
- 玩家：要破產的月份被說成平穩，會讓人忽略倒數。鐵道迷：無。開發：一個 case 和一個測試，不動 GameCore。美術：無。音樂：無。

### P3-2 從「資料」再開上個月月報，關掉後回到地圖，不是回到「資料」

- **在哪**：`RailwayGameApp/Views/EconomyPanel.swift` 的「第 N 個月月報…」把 `screen.panel` 換成 `.monthEnd`（#1520），月報是另一張 sheet，關掉後 `screen.panel` 是 `nil`。
- **怎麼重現**：（靜態推得，UNVERIFIED，要 Simulator 或實機）玩過一個月，打開「資料」→「第 1 個月月報…」→「完成」。
- **建議修法**：月報從「資料」打開時記下來處，關掉後把 `screen.panel` 設回 `.economy`；或在「資料」裡用 `NavigationLink` 推進月報卡，不換 sheet。
- 玩家：看完要再點一次「資料」，多一步。鐵道迷：無。開發：App 一處，UI 測試在 full lane 補。美術：無。音樂：無。

### P3-3 讀檔或繼續之後，「資料」的「上個月月報」不見，要等下個月結算

- **在哪**：`GameSession.lastMonthReport` 只存在記憶體（`SecretaryRoom.swift` 的 `closeMonth` 設定），不在新聞紀錄或存檔裡；離開 App 再「繼續」是新的 `GameSession`。
- **怎麼重現**：玩過月底、讓月報出現，回開始畫面再「繼續」，打開「資料」，沒有「第 N 個月月報…」那一列。
- **建議修法**：開局（`begin`／`restoreNews`）時，若現在不是第 0 個月，用 `MonthlyReport.make(month: 現在的月 − 1, in: world, baseline: nil)` 補一份（基準沒有了，「成長最多的車站」那段會空），或把上一份月報的數字寫進 `NewsLog`（不動 GameCore 存檔）。
- 玩家：關掉 App 再回來就看不到上個月的報告。鐵道迷：無。開發：GamePresentation 一處加一個測試。美術：無。音樂：無。

### P3-4 回報問題的「遊戲」一行，無限資金的局寫的是不會動的餘額

- **在哪**：`Sources/GamePresentation/ProblemReport.swift` 的 `problemReportGame` 用 `world.economy.balance.moneyText`；無限資金時餘額停在開局的數字（存檔清單已經寫「∞」，`SaveSummary.fundsText`）。
- **怎麼重現**：新遊戲選「資金：無限」，蓋一些東西，遊戲選單 →「回報問題」，「遊戲：」那行寫 $3,000,000。
- **建議修法**：照 `SaveSummary` 的寫法，`unlimitedFunds` 時寫「∞」。
- 玩家：看不到，但回報讀起來會誤會。鐵道迷：無。開發：一行。美術：無。音樂：無。

## 4. 沒有驗證的

- 實機、Simulator：UNVERIFIED（這輪不用 macOS runner）。P3-2 只靠讀程式。
- iCloud 存檔同步（`SaveSync`，決策 397）只有既有的 Linux 測試（假資料夾），真的 iCloud 沒有試。
- 高鐵、宜蘭線示範和平溪挑戰要讀 `RealRailways`，這輪沒有用無頭方式開；存檔大小上限 64 MB（`SharedNetwork.maximumBytes`）只對照了新竹的 0.78 MB。

## 5. 跨年的經營（VERIFIED，Linux release 建置）

新局（種子 1，`third-town` 腳本蓋兩條線、玩 4 天），借滿 $5,000,000，再買 41 列車把錢花到剩 $128,799，然後玩 400 天，每 7 天存→讀→繼續；每天在 00:01 記一次餘額（整點與午夜的結算都已入帳），比「餘額的變化」和帳上那一天的現金淨流量（`FinanceSummary.netCashFlow`）：

- 399 天逐日完全相同；唯一不同的是第 4 天，那是腳本在記第一筆餘額之前借款、買車的那天，差額正好是借入減買車（量法造成，不是錯帳）。
- 第 360 天結第 1 年決算（`accounts.years == [0]`），讀回的世界與存前相同。
- 這一局線路賺錢，現金沒有轉負；轉負與破產走 §2 的挑戰那一列。
- 指令（臨時測試類別 `ZZBughuntEconomyTests`，沒有提交）：`swift build -c release -Xswiftc -enable-testing --build-tests`，`BH_DAYS=400 swift test -c release --skip-build --filter ZZBughuntEconomyTests`（約 5 分鐘；debug 每遊戲天約 25 秒，跑不完）。
